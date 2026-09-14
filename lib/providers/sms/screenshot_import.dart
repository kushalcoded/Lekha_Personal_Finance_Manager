/// Turning a payments-app screenshot into detected transactions.
///
/// SMS detection is hit and miss on an iPhone, but every payment app shows a
/// history you can screenshot. The model reads the rows; everything here is
/// deciding which of them are new, and it is pure so that can be tested.
library;

import '../../models/expense/expense_model.dart';
import '../../models/pending/pending_transaction.dart';

/// One payment read off a screenshot.
class ScreenshotPayment {
  final double amount;
  final String? merchant;
  final DateTime when;

  const ScreenshotPayment({
    required this.amount,
    required this.merchant,
    required this.when,
  });
}

/// The payments in a model reply: money that left, that went through, with an
/// amount and a date. Received money, failed and pending rows are not spends.
List<ScreenshotPayment> paymentsFromScreenshot(
  Map<String, dynamic> reply, {
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <ScreenshotPayment>[];
  for (final row in (reply['items'] as List? ?? const []).whereType<Map>()) {
    if (row['isDebit'] != true) continue;
    final status = '${row['status'] ?? 'success'}'.toLowerCase();
    if (status == 'failed' || status == 'pending') continue;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) continue;

    final date = DateTime.tryParse('${row['date']}');
    if (date == null) continue; // nowhere to put it
    var day = DateTime(date.year, date.month, date.day);
    // A history shows "12 Dec" without a year. Read in January, the model may
    // still call that this year — which is in the future, so it was last year.
    if (day.isAfter(today)) day = DateTime(day.year - 1, day.month, day.day);

    final time = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch('${row['time']}');
    final when = time == null
        // No time shown: noon, a fixed point, so the same row read from two
        // screenshots lands on the same moment.
        ? DateTime(day.year, day.month, day.day, 12)
        : DateTime(
            day.year,
            day.month,
            day.day,
            int.parse(time.group(1)!).clamp(0, 23),
            int.parse(time.group(2)!).clamp(0, 59),
          );
    out.add(
      ScreenshotPayment(
        amount: amount,
        merchant: cleanMerchant(row['merchant']),
        when: when,
      ),
    );
  }
  return out;
}

/// Which [payments] are new, as pending rows ready to store.
///
/// Screenshots overlap — today's history repeats yesterday's — and the same
/// payment may already be here from an SMS or typed in by hand. So a payment
/// counts as known when this day already holds that many of that amount,
/// among detections (whatever became of them) and expenses not already
/// linked to one. Counting rather than matching keeps two real ₹50 teas on the
/// same day as two.
({List<PendingTransaction> fresh, int known}) pendingFromScreenshot(
  List<ScreenshotPayment> payments, {
  required String app,
  required List<PendingTransaction> existing,
  required List<Expense> expenses,
  required DateTime now,
}) {
  String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  String slot(DateTime d, double amount) =>
      '${dayKey(d)}|${amount.toStringAsFixed(2)}';

  final linked = {
    for (final t in existing)
      if (t.linkedExpenseId != null) t.linkedExpenseId!,
  };
  final alreadyHere = <String, int>{};
  for (final t in existing) {
    final k = slot(t.dateTime, t.amount);
    alreadyHere[k] = (alreadyHere[k] ?? 0) + 1;
  }
  for (final e in expenses) {
    if (linked.contains(e.id)) continue;
    final k = slot(e.date, e.amount);
    alreadyHere[k] = (alreadyHere[k] ?? 0) + 1;
  }
  final ids = {for (final t in existing) t.id};

  final label = _label(app);
  final seenInThisOne = <String, int>{};
  final fresh = <PendingTransaction>[];
  var known = 0;
  for (final p in payments) {
    final k = slot(p.when, p.amount);
    final nth = seenInThisOne[k] = (seenInThisOne[k] ?? 0) + 1;
    // Readable and stable, so the same row read again gets the same id.
    final id =
        'shot_${dayKey(p.when)}_${p.amount.toStringAsFixed(2)}_'
        '${_slug(p.merchant)}_$nth';
    if (ids.contains(id) || nth <= (alreadyHere[k] ?? 0)) {
      known++;
      continue;
    }
    fresh.add(
      PendingTransaction(
        id: id,
        amount: p.amount,
        dateTime: p.when,
        rawBody: label,
        createdAt: now,
        merchant: p.merchant,
      ),
    );
  }
  return (fresh: fresh, known: known);
}

/// "Google Pay · UPI": a shape the card's sender label shows exactly as it is.
String _label(String app) {
  final name = app.replaceAll(RegExp(r'[:\-—·]'), ' ').trim();
  final short = name.isEmpty
      ? 'Screenshot'
      : (name.length > 24 ? name.substring(0, 24).trim() : name);
  return '$short · UPI';
}

String _slug(String? merchant) {
  final s = (merchant ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return s.isEmpty ? 'x' : (s.length > 20 ? s.substring(0, 20) : s);
}
