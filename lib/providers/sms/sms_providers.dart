import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/pending/pending_transaction.dart';
import '../../services/gemini_service.dart';
import '../../services/storage/hive_service.dart';
import '../../services/supabase/supabase_service.dart';
import '../ai_providers.dart';

const _channel = MethodChannel('lekha/sms');

/// The amount+time dedup rule: an identical amount within a short window is the
/// same transaction — a bank + UPI double-SMS, or a re-sent/duplicate message.
/// Checks across all stored statuses so a dismissed/added one isn't re-surfaced.
bool isDuplicateTransaction(
  List<PendingTransaction> existing,
  double amount,
  DateTime dateTime, {
  Duration window = const Duration(minutes: 2),
}) {
  return existing.any(
    (e) =>
        (e.amount - amount).abs() < 0.01 &&
        e.dateTime.difference(dateTime).abs() <= window,
  );
}

/// Drains the native SMS queue, parses new debits via Gemini (AI-first), and
/// stores them as pending transactions. Nothing here needs network unless a
/// candidate actually reaches Gemini.
class SmsCaptureService {
  final GeminiService _gemini;

  SmsCaptureService(this._gemini);

  Future<bool> hasPermission() async {
    try {
      return (await _channel.invokeMethod<bool>('hasPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return (await _channel.invokeMethod<bool>('requestPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Read the native queue (Android) and the cloud queue (iPhone-forwarded
  /// SMS) → parse new ones → store. Returns how many new pending transactions
  /// were added. Already-seen entries are skipped, and both queues keep
  /// unparsed entries so an offline failure is retried next time.
  Future<int> sync() async {
    if (!_gemini.isConfigured) return 0; // AI-first: nothing to parse without it
    var added = 0;
    if (!kIsWeb) added += await _syncNativeQueue();
    added += await _syncCloudQueue();
    return added;
  }

  Future<int> _syncNativeQueue() async {
    String raw;
    try {
      raw = await _channel.invokeMethod<String>('readQueue') ?? '[]';
    } catch (_) {
      return 0;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) return 0;

    var added = 0;
    for (final item in decoded) {
      if (item is! Map) continue;
      final hash = item['hash']?.toString() ?? '';
      final body = item['body']?.toString() ?? '';
      final ts = (item['timestamp'] as num?)?.toInt();
      if (hash.isEmpty || body.isEmpty) continue;
      final dateTime = ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.now();
      if (await _ingest(hash: hash, body: body, dateTime: dateTime)) added++;
    }
    return added;
  }

  /// Drain SMS forwarded by an iPhone via the Shortcuts → ingest-sms pipeline
  /// (see SETUP_IOS_SMS.md). Same parse/dedup as the native queue. Rows are
  /// only marked done once Gemini has answered for them, so an offline run
  /// leaves them queued for retry.
  Future<int> _syncCloudQueue() async {
    List<dynamic> rows;
    try {
      final client = SupabaseService.client;
      if (client.auth.currentUser == null) return 0;
      rows = await client
          .from('ingested_sms')
          .select('id, body, received_at')
          .eq('status', 'new')
          .order('received_at')
          .limit(25);
    } catch (_) {
      return 0; // Supabase unconfigured/offline — retry on the next sync.
    }

    var added = 0;
    final done = <String>[];
    final hive = HiveService();
    for (final row in rows.whereType<Map>()) {
      final id = row['id']?.toString() ?? '';
      final body = row['body']?.toString() ?? '';
      if (id.isEmpty || body.isEmpty) continue;
      final hash = 'cloud_$id';
      final dateTime =
          DateTime.tryParse(row['received_at']?.toString() ?? '') ??
          DateTime.now();
      if (await _ingest(hash: hash, body: body, dateTime: dateTime)) added++;
      // Seen = Gemini responded (kept or filtered) — safe to retire the row.
      if (hive.isSmsSeen(hash)) done.add(id);
    }

    if (done.isNotEmpty) {
      try {
        await SupabaseService.client
            .from('ingested_sms')
            .update({'status': 'done'})
            .inFilter('id', done);
      } catch (_) {
        // Re-marking fails harmlessly: seen-hash dedup skips them next drain.
      }
    }
    return added;
  }

  /// The per-user token the iPhone Shortcut authenticates with. Returns the
  /// existing one or creates it. Null when signed out / Supabase unavailable.
  Future<String?> ensureIngestToken() async {
    try {
      final client = SupabaseService.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return null;
      final existing = await client
          .from('ingest_tokens')
          .select('token')
          .eq('user_id', userId)
          .limit(1);
      if (existing.isNotEmpty) {
        return existing.first['token'] as String?;
      }
      final token =
          const Uuid().v4().replaceAll('-', '') +
          const Uuid().v4().replaceAll('-', '');
      await client.from('ingest_tokens').insert({
        'token': token,
        'user_id': userId,
      });
      return token;
    } catch (_) {
      return null;
    }
  }

  /// Debug/testing: run a pasted SMS body through the full pipeline as if it
  /// had just arrived. Always processed (fresh hash).
  Future<bool> simulate(String body) {
    final now = DateTime.now();
    return _ingest(
      hash: 'sim_${now.microsecondsSinceEpoch}',
      body: body,
      dateTime: now,
    );
  }

  Future<bool> _ingest({
    required String hash,
    required String body,
    required DateTime dateTime,
  }) async {
    final hive = HiveService();
    if (hive.isSmsSeen(hash)) return false;
    try {
      final parsed = await _gemini.parseSmsTransaction(body);
      await hive.markSmsSeen(hash); // got a response — don't re-parse this one
      final isFinancial = parsed['isFinancial'] == true;
      final isDebit = parsed['isDebit'] == true;
      final amount = (parsed['amount'] as num?)?.toDouble() ?? 0;
      if (!isFinancial || !isDebit || amount <= 0) return false;
      if (isDuplicateTransaction(
        hive.getPendingTransactions(),
        amount,
        dateTime,
      )) {
        return false;
      }
      await hive.savePendingTransaction(
        PendingTransaction(
          id: hash,
          amount: amount,
          dateTime: dateTime,
          rawBody: body,
          createdAt: DateTime.now(),
        ),
      );
      return true;
    } catch (_) {
      // Offline / bad response: leave it unseen so the next open retries it.
      return false;
    }
  }
}

final smsCaptureServiceProvider = Provider<SmsCaptureService>((ref) {
  return SmsCaptureService(ref.read(geminiServiceProvider));
});

/// The pending (undecided) detected transactions, newest first.
final pendingTransactionsProvider =
    StateNotifierProvider<
      PendingTransactionsNotifier,
      List<PendingTransaction>
    >((ref) {
      return PendingTransactionsNotifier();
    });

class PendingTransactionsNotifier
    extends StateNotifier<List<PendingTransaction>> {
  PendingTransactionsNotifier() : super(const []) {
    refresh();
  }

  void refresh() {
    state = HiveService()
        .getPendingTransactions()
        .where((t) => t.status == PendingStatus.pending)
        .toList();
  }

  Future<void> markAdded(String id, String expenseId) async {
    final matches = HiveService().getPendingTransactions().where(
      (e) => e.id == id,
    );
    if (matches.isEmpty) return;
    await HiveService().savePendingTransaction(
      matches.first.copyWith(
        status: PendingStatus.added,
        linkedExpenseId: expenseId,
      ),
    );
    refresh();
  }

  Future<void> dismiss(String id) async {
    final matches = HiveService().getPendingTransactions().where(
      (e) => e.id == id,
    );
    if (matches.isEmpty) return;
    await HiveService().savePendingTransaction(
      matches.first.copyWith(status: PendingStatus.dismissed),
    );
    refresh();
  }
}
