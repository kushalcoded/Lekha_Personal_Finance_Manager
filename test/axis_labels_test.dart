import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/analytics/widgets/axis_labels.dart';

/// A cycle's worth of "Sep 14" labels under a phone-width chart printed on top
/// of each other.
void main() {
  const style = TextStyle(fontSize: 11);
  final days = [for (var d = 1; d <= 31; d++) 'Sep $d'];

  test('a month of days on a phone gets spaced-out labels', () {
    final step = axisLabelStep(
      width: 300,
      labels: days,
      style: style,
      textScaler: TextScaler.noScaling,
    );
    expect(step, greaterThan(1));
    // Room for every shown label: the gap between two of them is wider than
    // the widest label plus the edge nudge.
    expect(300 / 30 * step, greaterThanOrEqualTo(11 * 6 * 1.8));
  });

  test('a few labels on a wide chart all show', () {
    expect(
      axisLabelStep(
        width: 900,
        labels: const ['Jan', 'Feb', 'Mar'],
        style: style,
        textScaler: TextScaler.noScaling,
      ),
      1,
    );
  });

  test('the latest point is always labelled', () {
    for (final step in [1, 2, 3, 5]) {
      expect(axisLabelShown(30, 31, step), isTrue);
    }
    expect(axisLabelShown(29, 31, 2), isFalse);
  });
}
