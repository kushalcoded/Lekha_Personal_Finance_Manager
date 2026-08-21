import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:personal_expanse_tracker/utils/formatters/formatters.dart';

/// Sync timestamps are stored UTC on purpose, and that is defended by
/// `sync_timestamp_test.dart`. What nothing defended was the other end: every
/// formatter rendered whatever wall-clock fields it was handed, so a UTC value
/// printed the UTC day and "Last synced 20/08" appeared for a sync that
/// happened on the 21st.
///
/// There was no test anywhere asserting a *rendered string* — which is exactly
/// how it shipped.
///
/// Note these assertions are only meaningful off UTC. On a machine at UTC+0
/// they pass trivially; they earn their keep everywhere else, and the bug was
/// reported from IST.
void main() {
  group('formatters render the reader\'s day, not the stored one', () {
    // 22:30 UTC is already the next day everywhere east of UTC+01:30.
    final instant = DateTime.utc(2026, 8, 20, 22, 30);

    test('the same instant renders identically however it is expressed', () {
      // The real invariant, and the one that was broken: a UTC DateTime and its
      // local twin are the same moment, so they must print the same thing.
      expect(
        AppFormatters.formatDate(instant),
        AppFormatters.formatDate(instant.toLocal()),
      );
      expect(
        AppFormatters.formatTime(instant),
        AppFormatters.formatTime(instant.toLocal()),
      );
      expect(
        AppFormatters.formatDateTime(instant),
        AppFormatters.formatDateTime(instant.toLocal()),
      );
    });

    test('a UTC instant renders as the local calendar day', () {
      expect(
        AppFormatters.formatDate(instant, format: 'dd/MM/yyyy'),
        DateFormat('dd/MM/yyyy').format(instant.toLocal()),
      );
    });

    test('a UTC instant renders as the local clock time', () {
      expect(
        AppFormatters.formatTime(instant),
        DateFormat('HH:mm').format(instant.toLocal()),
      );
    });

    test('a local value is untouched', () {
      final local = DateTime(2026, 8, 21, 9, 5);
      expect(AppFormatters.formatDate(local, format: 'dd/MM/yyyy'), '21/08/2026');
      expect(AppFormatters.formatTime(local), '09:05');
    });
  });

  // getRelativeTime compares instants, so its short branches were always
  // right — it is the fallback past seven days that reached formatDate.
  group('getRelativeTime', () {
    test('recent instants read as elapsed time regardless of zone', () {
      final now = DateTime.now();
      expect(AppFormatters.getRelativeTime(now.toUtc()), 'just now');
      expect(
        AppFormatters.getRelativeTime(
          now.subtract(const Duration(hours: 3)).toUtc(),
        ),
        '3h ago',
      );
    });

    test('past seven days it falls back to a date, in local terms', () {
      final old = DateTime.now().subtract(const Duration(days: 30));
      expect(
        AppFormatters.getRelativeTime(old.toUtc()),
        AppFormatters.formatDate(old),
      );
    });
  });
}
