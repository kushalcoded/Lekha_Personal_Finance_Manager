import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/pending/pending_transaction.dart';
import '../../services/gemini_service.dart';
import '../../services/storage/hive_service.dart';
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

  /// Read the native queue → parse new ones → store. Returns how many new
  /// pending transactions were added. Already-seen entries are skipped, and the
  /// queue is read-only so an offline failure is retried next time.
  Future<int> sync() async {
    if (!_gemini.isConfigured) return 0; // AI-first: nothing to parse without it
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
