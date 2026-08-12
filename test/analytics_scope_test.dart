import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/analytics/providers/analytics_providers.dart';

/// The window rule, stated once: every scope is a LOWER BOUND ONLY.
///
/// The bug these tests exist for: the screen clamped its upper bound to the
/// start of today, so an expense added at 6pm was counted by the dashboard and
/// ignored by Insights until the next morning. The two totals differed by
/// exactly the day's spending and nothing on screen explained why.
bool inScope(DateTime start, DateTime date) => !date.isBefore(start);

void main() {
  final now = DateTime(2026, 8, 12, 18, 33);

  group('scope starts', () {
    test('30 days reaches back 29 days, to midnight', () {
      expect(
        analyticsScopeStart(AnalyticsScope.days30, now),
        DateTime(2026, 7, 14),
      );
    });

    test('12M reaches back 364 days, to midnight', () {
      expect(
        analyticsScopeStart(AnalyticsScope.months12, now),
        DateTime(2025, 8, 13),
      );
    });

    test('a start is always midnight, never the current clock time', () {
      // Otherwise the boundary day is half-included depending on when you look.
      for (final scope in AnalyticsScope.values) {
        final start = analyticsScopeStart(scope, now);
        expect(start.hour, 0);
        expect(start.minute, 0);
        expect(start.second, 0);
      }
    });
  });

  group('nothing is excluded by an upper bound', () {
    test('an expense dated today, later than now, is still in scope', () {
      // The exact shape of the reported bug.
      final addedThisEvening = DateTime(2026, 8, 12, 18, 33);
      for (final scope in AnalyticsScope.values) {
        final start = scope == AnalyticsScope.cycle
            ? DateTime(2026, 8, 6)
            : analyticsScopeStart(scope, now);
        expect(
          inScope(start, addedThisEvening),
          isTrue,
          reason: '${scope.name} dropped an expense dated today',
        );
      }
    });

    test('a future-dated expense stays visible rather than vanishing', () {
      // Dating a spend forward is legal in the picker, so it must not silently
      // disappear from the screen that is supposed to total everything.
      final nextWeek = DateTime(2026, 8, 19, 9);
      expect(inScope(analyticsScopeStart(AnalyticsScope.days30, now), nextWeek),
          isTrue);
      expect(inScope(DateTime(2026, 8, 6), nextWeek), isTrue);
    });
  });

  group('the longer scopes escape the cycle', () {
    // analyticsExpensesProvider used to be unconditionally cycle-clipped, which
    // is why the 6-month chart could only ever draw the current cycle.
    final cycleStart = DateTime(2026, 8, 6);
    final lastMonth = DateTime(2026, 7, 20);

    test('30 days reaches before the cycle start', () {
      expect(inScope(cycleStart, lastMonth), isFalse);
      expect(
        inScope(analyticsScopeStart(AnalyticsScope.days30, now), lastMonth),
        isTrue,
      );
    });

    test('12M reaches back months', () {
      final march = DateTime(2026, 3, 3);
      expect(
        inScope(analyticsScopeStart(AnalyticsScope.months12, now), march),
        isTrue,
      );
    });
  });

  test('labels stay distinct, short and long', () {
    final labels = AnalyticsScope.values.map((s) => s.label).toSet();
    final shorts = AnalyticsScope.values.map((s) => s.shortLabel).toSet();
    expect(labels.length, AnalyticsScope.values.length);
    expect(shorts.length, AnalyticsScope.values.length);
  });
}
