import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/core/navigation/navigation_models.dart';
import 'package:personal_expanse_tracker/screens/analytics/providers/analytics_providers.dart';

/// A swipe on Insights moves through the scopes first and only reaches the
/// tabs once there is no scope left to move to. `adjacentScope` returning the
/// scope it was given is the signal to hand the gesture on, so that behaviour
/// is the whole contract.
void main() {
  group('adjacentScope', () {
    test('moves forward through the scopes', () {
      expect(
        adjacentScope(AnalyticsScope.cycle, forward: true),
        AnalyticsScope.days30,
      );
      expect(
        adjacentScope(AnalyticsScope.days30, forward: true),
        AnalyticsScope.months12,
      );
    });

    test('moves back again', () {
      expect(
        adjacentScope(AnalyticsScope.months12, forward: false),
        AnalyticsScope.days30,
      );
      expect(
        adjacentScope(AnalyticsScope.days30, forward: false),
        AnalyticsScope.cycle,
      );
    });

    test('stops at the ends rather than wrapping', () {
      // Wrapping would be a glitch, not a move — and it is also what tells the
      // caller the swipe now belongs to the tabs.
      expect(
        adjacentScope(AnalyticsScope.months12, forward: true),
        AnalyticsScope.months12,
      );
      expect(
        adjacentScope(AnalyticsScope.cycle, forward: false),
        AnalyticsScope.cycle,
      );
    });
  });

  test('Insights has a tab on either side to hand the swipe to', () {
    // The edge case the swipe handler guards: if Insights were first or last,
    // one direction would have nowhere to go.
    final tabs = NavigationTab.values;
    final index = tabs.indexOf(NavigationTab.insights);
    expect(index, greaterThan(0));
    expect(index, lessThan(tabs.length - 1));
    expect(tabs[index - 1], NavigationTab.expenses);
    expect(tabs[index + 1], NavigationTab.debts);
  });
}
