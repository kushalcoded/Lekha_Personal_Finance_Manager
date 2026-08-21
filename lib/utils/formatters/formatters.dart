import 'package:intl/intl.dart';

/// Formatters for various data types
class AppFormatters {
  /// Format currency
  static String formatCurrency(double amount, {String symbol = '₹'}) {
    final normalized = amount.abs();
    final fraction = normalized - normalized.truncateToDouble();
    final decimals = fraction > 0.0001 ? 2 : 0;
    final pattern = decimals == 0 ? '#,##,##0' : '#,##,##0.00';
    final formatter = NumberFormat(pattern, 'en_IN');
    final sign = amount < 0 ? '-' : '';
    return '$sign$symbol${formatter.format(normalized)}';
  }

  /// Pick the wording that matches [count].
  ///
  /// For the noun and for the verb, since English needs both: "1 receivable is
  /// overdue", not "1 receivables are overdue" — which is what the daily
  /// notification actually said.
  static String plural(int count, String one, String many) =>
      count == 1 ? one : many;

  /// Format date to readable format.
  ///
  /// `.toLocal()` because `DateFormat` renders whatever wall-clock fields the
  /// DateTime carries: hand it a UTC value and it prints the UTC day, which
  /// east of Greenwich is yesterday for the whole first part of the morning.
  /// Several timestamps here are deliberately stored UTC, and this is the
  /// boundary where they become something a person reads. A no-op for a value
  /// that is already local.
  static String formatDate(DateTime date, {String format = 'MMM dd, yyyy'}) {
    try {
      final formatter = DateFormat(format);
      return formatter.format(date.toLocal());
    } catch (e) {
      return date.toString();
    }
  }

  /// Format date to time format. Local for the same reason as [formatDate] —
  /// and a clock time is off by the whole offset, not just at the boundary.
  static String formatTime(DateTime time, {String format = 'HH:mm'}) {
    try {
      final formatter = DateFormat(format);
      return formatter.format(time.toLocal());
    } catch (e) {
      return time.toString();
    }
  }

  /// Format date-time
  static String formatDateTime(DateTime dateTime) {
    return '${formatDate(dateTime)} at ${formatTime(dateTime)}';
  }

  /// Get relative time (e.g., "2 hours ago")
  static String getRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return formatDate(dateTime);
    }
  }

  /// Format percentage
  static String formatPercentage(double value, {int decimals = 1}) {
    return '${(value * 100).toStringAsFixed(decimals)}%';
  }
}
