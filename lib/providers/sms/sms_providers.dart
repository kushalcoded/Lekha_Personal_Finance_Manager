import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/category/expense_category.dart';
import '../../models/expense/expense_model.dart';
import '../../models/pending/pending_transaction.dart';
import '../../screens/expenses/utils/expense_helpers.dart';
import '../../services/gemini_service.dart';
import '../../services/storage/hive_service.dart';
import '../../services/supabase/supabase_service.dart';
import '../ai_providers.dart';
import '../auth/auth_provider.dart';
import '../payment/payment_method_providers.dart';
import '../storage/storage_providers.dart';

const _channel = MethodChannel('lekha/sms');

/// What the user tapped on a detection notification, keyed by SMS hash. The
/// buttons are handled by a native receiver that can't parse or store anything,
/// so the decision waits here until the app next drains the queue.
///
/// Anything malformed reads as "no decision" — a corrupt blob must not turn
/// into a silent auto-add.
Map<String, String> smsDecisions(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.value == 'add' || entry.value == 'ignore')
          entry.key.toString(): entry.value.toString(),
    };
  } catch (_) {
    return const {};
  }
}

/// When the transaction actually happened. Android hands us the SMS's own
/// timestamp, but the iPhone path only knows when the Shortcut POSTed — the
/// moment iOS got around to running it — so a batch delivered days late all
/// shared one wrong time. Prefer the date stated inside the message, ignore
/// implausible answers, and fall back to the delivery time.
DateTime resolveTransactionTime(Object? stated, {required DateTime fallback}) {
  final text = stated?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return fallback;
  final now = DateTime.now();
  // A bank never texts about tomorrow, and a model that guessed the year
  // wrong should not silently backdate an expense out of the cycle.
  if (parsed.isAfter(now.add(const Duration(days: 1)))) return fallback;
  if (parsed.isBefore(now.subtract(const Duration(days: 400)))) return fallback;
  // A date-only answer keeps the delivery clock time, so the row doesn't
  // claim a precision the message never gave.
  if (parsed.hour == 0 && parsed.minute == 0 && parsed.second == 0) {
    return DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      fallback.hour,
      fallback.minute,
    );
  }
  return parsed;
}

/// Words that make a message a spend. Deliberately narrower than the native
/// receiver's gate, which also lets `txn`/`transaction` through — fine for
/// deciding what to queue, too vague to book money on without the model.
const _debitWords = [
  'debited',
  'debit',
  'spent',
  'withdrawn',
  'deducted',
  'paid',
  'sent',
  'purchase',
];

/// Anything here means it isn't a spend, whatever else the text says.
const _notASpendWords = [
  'credited',
  'received',
  'refund',
  'reversal',
  'reversed',
  'otp',
  'one time password',
];

final _amountPattern = RegExp(
  r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  caseSensitive: false,
);

/// The amount a bank SMS is about, read without touching the network — or null
/// when the message doesn't clearly say, in which case the caller falls back to
/// the model.
///
/// Being wrong here is worse than being slow, so every uncertain case returns
/// null rather than guessing. The two failure modes worth naming: reading the
/// *available balance* as the spend, and treating a credit as a debit.
double? quickParseSms(String body) {
  final text = body.toLowerCase();
  if (_notASpendWords.any(text.contains)) return null;
  if (!_debitWords.any(text.contains)) return null;

  final match = _amountPattern.firstMatch(body);
  if (match == null) return null;

  // Indian bank templates lead with the transaction amount and trail with the
  // balance, so the FIRST match is the one meant. If a balance word sits just
  // before it, this message doesn't follow that shape — hand it to the model.
  final lead = text.substring(
    match.start - 24 < 0 ? 0 : match.start - 24,
    match.start,
  );
  if (lead.contains('bal') || lead.contains('avl')) return null;

  final amount = double.tryParse(match.group(1)!.replaceAll(',', ''));
  if (amount == null || amount <= 0) return null;
  return amount;
}

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
  final Ref _ref;

  SmsCaptureService(this._gemini, this._ref);

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

  /// Mirror the notification toggle to the native side — the SMS receiver runs
  /// with the app dead and can't read Hive. Returns false when the toggle is on
  /// but Android won't let us post, so Settings can say so instead of lying.
  Future<bool> setNotify(bool on) async {
    try {
      return (await _channel.invokeMethod<bool>('setNotify', on)) ?? false;
    } catch (_) {
      return false; // web / iOS: no receiver to configure
    }
  }

  /// Read the native queue (Android) and the cloud queue (iPhone-forwarded
  /// SMS) → parse new ones → store. Returns how many new pending transactions
  /// were added. Already-seen entries are skipped, and both queues keep
  /// unparsed entries so an offline failure is retried next time.
  /// Cloud round-trips are throttled: the foreground poll runs every few
  /// seconds so a native Android SMS appears almost instantly, but that
  /// cadence must not become three Supabase calls every few seconds — it
  /// would burn quota and battery for nothing. Local queues stay on the fast
  /// path; the network side runs at most once a minute, or immediately when
  /// [force] is set (app resume, manual sync).
  static const _cloudInterval = Duration(seconds: 60);
  DateTime? _lastCloudAt;

  Future<int> sync({bool force = false}) async {
    var added = 0;
    final now = DateTime.now();
    final cloudDue =
        force ||
        _lastCloudAt == null ||
        now.difference(_lastCloudAt!) >= _cloudInterval;

    // The local queue goes first. It needs no network, so nothing the user is
    // waiting to see should sit behind two Supabase round trips — which is
    // exactly what happened on resume, when the throttle is skipped and the
    // user is most likely watching the screen.
    if (!kIsWeb) added += await _syncNativeQueue();

    if (cloudDue) {
      _lastCloudAt = now;
      // Server-parsed detections need no local AI, so they are pulled even
      // when this device has none configured.
      added += await _pullDetected();
      await _pushDetected();
      if (_gemini.isConfigured) {
        // Fallback drain: rows the server couldn't parse are still 'new'.
        added += await _syncCloudQueue();
      }
    }

    // Confirm anything the local read guessed at. Deliberately not awaited:
    // the cards are already on screen, and this must not delay the next poll.
    unawaited(verifyProvisional());
    return added;
  }

  /// Adopt detections the server parsed (iPhone SMS are parsed the moment
  /// they arrive) and status changes made on other devices. This is what
  /// removes the "nothing shows up until I open the app" gap on iOS.
  Future<int> _pullDetected() async {
    List<dynamic> rows;
    try {
      final client = SupabaseService.client;
      if (client.auth.currentUser == null) return 0;
      rows = await client
          .from('detected_transactions')
          .select(
            'id, amount, occurred_at, raw_body, status, linked_expense_id',
          )
          .order('occurred_at', ascending: false)
          .limit(100);
    } catch (_) {
      return 0; // offline / table not created yet
    }

    final hive = HiveService();
    final local = {for (final t in hive.getPendingTransactions()) t.id: t};
    var added = 0;
    for (final row in rows.whereType<Map>()) {
      final id = row['id']?.toString();
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (id == null || id.isEmpty || amount <= 0) continue;
      final status = _statusFrom(row['status']);
      final existing = local[id];
      if (existing != null) {
        // Terminal beats pending, whichever device decided it.
        if (existing.status == PendingStatus.pending &&
            status != PendingStatus.pending) {
          await hive.savePendingTransaction(
            existing.copyWith(
              status: status,
              linkedExpenseId: row['linked_expense_id']?.toString(),
            ),
          );
        }
        continue;
      }
      if (status != PendingStatus.pending) {
        // Already handled elsewhere: remember it so the local dedup and the
        // seen-set don't resurrect it, but don't show a card.
        await hive.markSmsSeen(id);
        continue;
      }
      final occurred =
          DateTime.tryParse(row['occurred_at']?.toString() ?? '') ??
          DateTime.now();
      final body = row['raw_body']?.toString() ?? '';
      if (isDuplicateTransaction(
        hive.getPendingTransactions(),
        amount,
        occurred,
      )) {
        continue;
      }
      await hive.markSmsSeen(id);
      await hive.savePendingTransaction(
        PendingTransaction(
          id: id,
          amount: amount,
          dateTime: occurred,
          rawBody: body,
          createdAt: DateTime.now(),
        ),
      );
      added++;
    }
    return added;
  }

  /// Publish this device's detections and decisions so the others match —
  /// an Android-detected SMS shows up on the web app, and adding one here
  /// clears the card everywhere.
  Future<void> _pushDetected() async {
    try {
      final client = SupabaseService.client;
      final user = client.auth.currentUser;
      if (user == null) return;
      final rows = HiveService()
          .getPendingTransactions()
          .map(
            (t) => {
              'id': t.id,
              'user_id': user.id,
              'amount': t.amount,
              'occurred_at': t.dateTime.toIso8601String(),
              // The message itself never leaves the device that received it —
              // only "HDFC Bank · UPI". Other devices show that on the card,
              // and nobody's bank texts sit in the shared database. The label
              // is idempotent, so pulling and re-pushing a row keeps it.
              'raw_body': smsSenderLabel(t.rawBody),
              'status': t.status.name,
              'linked_expense_id': t.linkedExpenseId,
              'updated_at': DateTime.now().toIso8601String(),
            },
          )
          .toList();
      if (rows.isEmpty) return;
      await client.from('detected_transactions').upsert(rows);
    } catch (_) {
      // Offline or table missing — the next sync retries.
    }
  }

  static PendingStatus _statusFrom(Object? raw) {
    final name = raw?.toString() ?? '';
    return PendingStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => PendingStatus.pending,
    );
  }

  Future<int> _syncNativeQueue() async {
    String raw;
    var decisions = const <String, String>{};
    try {
      raw = await _channel.invokeMethod<String>('readQueue') ?? '[]';
      decisions = smsDecisions(
        await _channel.invokeMethod<String>('readDecisions') ?? '{}',
      );
    } catch (_) {
      return 0;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) return 0;

    var added = 0;
    final handled = <String>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final hash = item['hash']?.toString() ?? '';
      final body = item['body']?.toString() ?? '';
      final ts = (item['timestamp'] as num?)?.toInt();
      if (hash.isEmpty || body.isEmpty) continue;
      final decision = decisions[hash];

      // Ignored from the notification: retire it without spending a model call.
      if (decision == 'ignore') {
        await HiveService().markSmsSeen(hash);
        handled.add(hash);
        continue;
      }

      final dateTime = ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.now();
      if (await _ingest(
        hash: hash,
        body: body,
        dateTime: dateTime,
        autoAdd: decision == 'add',
      )) {
        added++;
      }
      // Only clear once the parse actually resolved — an offline failure leaves
      // the decision queued so the next drain still honours the tap.
      if (decision != null && HiveService().isSmsSeen(hash)) handled.add(hash);
    }

    if (handled.isNotEmpty) {
      try {
        await _channel.invokeMethod<void>('clearDecisions', handled);
      } catch (_) {
        // Harmless: a stale decision only re-applies to an already-seen hash.
      }
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

    // Retire processed rows older than 30 days so the table doesn't grow
    // forever. The recent window stays so lastCloudSmsAt() keeps feeding the
    // iPhone-guide health card.
    try {
      await SupabaseService.client
          .from('ingested_sms')
          .delete()
          .eq('status', 'done')
          .lt(
            'received_at',
            DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
          );
    } catch (_) {
      // Cleanup is best-effort; rows just wait for the next drain.
    }
    return added;
  }

  /// When the most recent iPhone-forwarded SMS arrived (any status), or null
  /// if none ever did / Supabase unavailable. Surfaced as a health hint —
  /// iOS silently disables Shortcuts automations sometimes.
  Future<DateTime?> lastCloudSmsAt() async {
    try {
      final client = SupabaseService.client;
      if (client.auth.currentUser == null) return null;
      final rows = await client
          .from('ingested_sms')
          .select('received_at')
          .order('received_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      return DateTime.tryParse(rows.first['received_at']?.toString() ?? '');
    } catch (_) {
      return null;
    }
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
    bool autoAdd = false,
  }) async {
    final hive = HiveService();
    if (hive.isSmsSeen(hash)) return false;

    // Read it locally first. A card the user can act on costs nothing and no
    // network, and the model confirms it a moment later. Not used for autoAdd:
    // booking an expense straight from a regex would put a possibly-wrong
    // amount somewhere corrections are no longer allowed to reach.
    if (!autoAdd) {
      final quick = quickParseSms(body);
      if (quick != null) {
        await hive.markSmsSeen(hash);
        if (isDuplicateTransaction(
          hive.getPendingTransactions(),
          quick,
          dateTime,
        )) {
          return false;
        }
        await hive.savePendingTransaction(
          PendingTransaction(
            id: hash,
            amount: quick,
            dateTime: dateTime,
            rawBody: body,
            createdAt: DateTime.now(),
            provisional: true,
          ),
        );
        return true;
      }
    }

    // Nothing the regex would commit to — the model is the only way through,
    // so without it this one waits for the next drain.
    if (!_gemini.isConfigured) return false;
    try {
      final parsed = await _gemini.parseSmsTransaction(body);
      await hive.markSmsSeen(hash); // got a response — don't re-parse this one
      final isFinancial = parsed['isFinancial'] == true;
      final isDebit = parsed['isDebit'] == true;
      final amount = (parsed['amount'] as num?)?.toDouble() ?? 0;
      if (!isFinancial || !isDebit || amount <= 0) return false;
      final when = resolveTransactionTime(parsed['when'], fallback: dateTime);
      if (isDuplicateTransaction(hive.getPendingTransactions(), amount, when)) {
        return false;
      }
      final pending = PendingTransaction(
        id: hash,
        amount: amount,
        dateTime: when,
        rawBody: body,
        createdAt: DateTime.now(),
      );
      if (autoAdd) {
        await _bookExpense(pending);
        return false; // handled, not waiting for review
      }
      await hive.savePendingTransaction(pending);
      return true;
    } catch (_) {
      // Offline / bad response: leave it unseen so the next open retries it.
      return false;
    }
  }

  /// How many rows are verified at once. Enough to clear a burst quickly
  /// without opening a dozen sockets on a phone radio.
  static const _verifyBatch = 4;
  bool _verifying = false;

  /// Second-guess the local read. Cards created by [quickParseSms] are already
  /// on screen; this corrects the amount or date the model disagrees with, and
  /// removes rows it says were never a spend.
  ///
  /// Only ever touches rows that are still pending — once the user has added or
  /// dismissed one, their decision stands and nothing here may change it.
  Future<void> verifyProvisional() async {
    if (_verifying || !_gemini.isConfigured) return;
    _verifying = true;
    try {
      final rows = HiveService()
          .getPendingTransactions()
          .where((t) => t.provisional && t.status == PendingStatus.pending)
          .toList();
      for (var i = 0; i < rows.length; i += _verifyBatch) {
        final batch = rows.skip(i).take(_verifyBatch).map(_verifyOne);
        await Future.wait(batch);
      }
    } finally {
      _verifying = false;
    }
  }

  Future<void> _verifyOne(PendingTransaction txn) async {
    final hive = HiveService();
    try {
      final parsed = await _gemini.parseSmsTransaction(txn.rawBody);

      // Re-read: the user may have decided on this card while we were waiting.
      final matches = hive.getPendingTransactions().where(
        (t) => t.id == txn.id,
      );
      if (matches.isEmpty) return;
      final current = matches.first;
      if (current.status != PendingStatus.pending) return;

      final isFinancial = parsed['isFinancial'] == true;
      final isDebit = parsed['isDebit'] == true;
      final amount = (parsed['amount'] as num?)?.toDouble() ?? 0;
      if (!isFinancial || !isDebit || amount <= 0) {
        // Not a spend after all — vanish, rather than leave the user to
        // dismiss something the app already knows is wrong.
        await hive.deletePendingTransaction(txn.id);
        return;
      }

      await hive.savePendingTransaction(
        current.copyWith(
          amount: amount,
          dateTime: resolveTransactionTime(
            parsed['when'],
            fallback: current.dateTime,
          ),
          provisional: false,
        ),
      );
    } catch (_) {
      // Offline or a bad response: the card stays as it is, still provisional,
      // and the next sync tries again.
    }
  }

  /// Book a detection the user already approved from the notification shade.
  /// The shade can't ask for a category, so it lands in the protected default
  /// and keeps its SMS trail — enough to find and re-file later.
  ///
  /// The payment method prefers the user's chosen default over sniffing the
  /// SMS: inference reads the sender name, so a card spend from a bank whose
  /// name contains "Bank" was being filed as a bank transfer.
  Future<void> _bookExpense(PendingTransaction txn) async {
    final expense = Expense(
      id: const Uuid().v4(),
      userId: _ref.read(currentUserIdProvider) ?? localUserId,
      amount: txn.amount,
      category: kProtectedCategoryName,
      description: smsSenderLabel(txn.rawBody),
      paymentMethod: resolveAutoPaymentMethod(
        _ref.read(defaultPaymentMethodProvider),
        inferPaymentMethod(txn.rawBody),
      ),
      date: txn.dateTime,
      createdAt: DateTime.now(),
    );
    await _ref.read(expensesProvider.notifier).addExpense(expense);
    await HiveService().savePendingTransaction(
      txn.copyWith(status: PendingStatus.added, linkedExpenseId: expense.id),
    );
  }
}

/// How long since the iPhone last forwarded an SMS, or null if it never has
/// / we can't tell. iOS silently disables Shortcuts automations, and the only
/// symptom is silence — so this is surfaced in Settings rather than buried in
/// the setup guide.
final iphoneSmsHealthProvider = FutureProvider<DateTime?>((ref) async {
  return ref.read(smsCaptureServiceProvider).lastCloudSmsAt();
});

final smsCaptureServiceProvider = Provider<SmsCaptureService>((ref) {
  return SmsCaptureService(ref.read(geminiServiceProvider), ref);
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
