import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:personal_expanse_tracker/providers/sms/sms_providers.dart';
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
  // Comparing rendered dates can only discriminate off UTC — at UTC+0 the two
  // sides are identical and these pass without proving anything. Rather than
  // let that rot into a silently vacuous test, say so out loud.
  final atUtc = DateTime.now().timeZoneOffset == Duration.zero;
  const vacuous =
      'This machine is at UTC, where a UTC value and its local twin render '
      'identically — nothing to tell apart. Run it anywhere with an offset.';

  // The parse behind Expense.date, and the one worth proving anywhere: the
  // *kind* of the result is checkable in every timezone, UTC included.
  group('parseCloudReceivedAt', () {
    test('a Z-suffixed string comes back local, never UTC', () {
      final parsed = parseCloudReceivedAt('2026-08-20T22:30:00Z');
      expect(
        parsed.isUtc,
        isFalse,
        reason: 'left UTC it becomes Expense.date and books the wrong day',
      );
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 8, 20, 22, 30).millisecondsSinceEpoch,
        reason: 'same instant, only the zone should change',
      );
    });

    test('an explicit offset is honoured, not ignored', () {
      final parsed = parseCloudReceivedAt('2026-08-20T22:30:00+05:30');
      expect(parsed.isUtc, isFalse);
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 8, 20, 17, 0).millisecondsSinceEpoch,
      );
    });

    test('junk falls back to now rather than throwing', () {
      expect(parseCloudReceivedAt(null).isUtc, isFalse);
      expect(parseCloudReceivedAt('not a date').isUtc, isFalse);
    });
  });

  group('formatters render the reader\'s day, not the stored one', () {
    // 22:30 UTC is already the next day everywhere east of UTC+01:30.
    final instant = DateTime.utc(2026, 8, 20, 22, 30);

    test(
      'the same instant renders identically however it is expressed',
      () {
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
      },
      skip: atUtc ? vacuous : null,
    );

    test(
      'a UTC instant renders as the local calendar day',
      () {
        expect(
          AppFormatters.formatDate(instant, format: 'dd/MM/yyyy'),
          DateFormat('dd/MM/yyyy').format(instant.toLocal()),
        );
      },
      skip: atUtc ? vacuous : null,
    );

    test('a UTC instant renders as the local clock time', () {
      expect(
        AppFormatters.formatTime(instant),
        DateFormat('HH:mm').format(instant.toLocal()),
      );
    }, skip: atUtc ? vacuous : null);

    test('a local value is untouched', () {
      final local = DateTime(2026, 8, 21, 9, 5);
      expect(
        AppFormatters.formatDate(local, format: 'dd/MM/yyyy'),
        '21/08/2026',
      );
      expect(AppFormatters.formatTime(local), '09:05');
    });
  });

  // "1 receivables are overdue" went out in the daily notification, so this is
  // not only a written-English nit — it buzzes the phone.
  group('plural', () {
    test('one takes the singular, everything else the plural', () {
      expect(
        AppFormatters.plural(1, 'receivable', 'receivables'),
        'receivable',
      );
      expect(
        AppFormatters.plural(2, 'receivable', 'receivables'),
        'receivables',
      );
      expect(
        AppFormatters.plural(0, 'receivable', 'receivables'),
        'receivables',
      );
    });

    test('works for the verb too, which is the half usually forgotten', () {
      expect(AppFormatters.plural(1, 'is', 'are'), 'is');
      expect(AppFormatters.plural(3, 'is', 'are'), 'are');
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
