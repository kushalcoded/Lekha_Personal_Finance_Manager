import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/analytics/providers/analytics_providers.dart';

/// Swiping the Insights screen moves through the scope tabs in the order they
/// are drawn. It stops at the ends: wrapping from 12M back to "this cycle"
/// would read as a glitch rather than a move.
void main() {
  test('swiping forward walks left to right', () {
    expect(
      adjacentScope(AnalyticsScope.cycle, forward: true),
      AnalyticsScope.days30,
    );
    expect(
      adjacentScope(AnalyticsScope.days30, forward: true),
      AnalyticsScope.months12,
    );
  });

  test('swiping back walks the other way', () {
    expect(
      adjacentScope(AnalyticsScope.months12, forward: false),
      AnalyticsScope.days30,
    );
    expect(
      adjacentScope(AnalyticsScope.days30, forward: false),
      AnalyticsScope.cycle,
    );
  });

  test('the ends hold instead of wrapping', () {
    expect(
      adjacentScope(AnalyticsScope.months12, forward: true),
      AnalyticsScope.months12,
    );
    expect(
      adjacentScope(AnalyticsScope.cycle, forward: false),
      AnalyticsScope.cycle,
    );
  });

  test('the order matches what the tabs show', () {
    // The swipe direction is only intuitive if it follows the drawn order.
    expect(AnalyticsScope.values, [
      AnalyticsScope.cycle,
      AnalyticsScope.days30,
      AnalyticsScope.months12,
    ]);
  });
}
