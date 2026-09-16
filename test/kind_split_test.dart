import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/analytics/models/analytics_models.dart';

/// The Insights panels describe everyday spending only, because rent is the
/// biggest expense most months and used to win every chart. The one section
/// that still sees everything is this split — so its shares have to be of
/// spending, and money that merely moved must stay out of them.
void main() {
  KindSplit split({
    double everyday = 0,
    double committed = 0,
    double invested = 0,
    double moved = 0,
    double income = 0,
  }) => KindSplit(
    everyday: everyday,
    committed: committed,
    invested: invested,
    moved: moved,
    income: income,
  );

  test('shares are of money spent, not of money that moved', () {
    // A SIP and a card-bill payment are big numbers that would swamp the bar
    // if they counted, and neither is spending.
    final s = split(
      everyday: 5000,
      committed: 15000,
      invested: 20000,
      moved: 12000,
      income: 46000,
    );
    expect(s.spent, 20000);
    expect(s.committedShare, 0.75);
    expect(s.everydayShare, 0.25);
  });

  test('the two shares always account for the whole bar', () {
    final s = split(everyday: 1, committed: 2);
    expect(s.committedShare + s.everydayShare, closeTo(1, 1e-9));
  });

  test('no spending yet is zero shares, not a division by zero', () {
    final s = split(income: 46000);
    expect(s.spent, 0);
    expect(s.committedShare, 0);
    expect(s.everydayShare, 0);
    expect(s.isEmpty, isFalse, reason: 'income is still worth showing');
  });

  test('a cycle with nothing at all is empty', () {
    expect(split().isEmpty, isTrue);
  });

  test('bills alone is a hundred per cent bills', () {
    final s = split(committed: 20000);
    expect(s.committedShare, 1);
    expect(s.everydayShare, 0);
  });
}
