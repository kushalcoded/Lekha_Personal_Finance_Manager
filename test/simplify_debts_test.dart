import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/debts/utils/simplify_debts.dart';

/// The reduction has one job nobody can eyeball: fewer payments that still
/// leave everybody exactly square. A bug here hands somebody a number to pay
/// that looks perfectly reasonable and is wrong.
void main() {
  double paidBy(List<Transfer> ts, String who) =>
      ts.where((t) => t.from == who).fold(0.0, (sum, t) => sum + t.amount);
  double receivedBy(List<Transfer> ts, String who) =>
      ts.where((t) => t.to == who).fold(0.0, (sum, t) => sum + t.amount);

  /// Everyone ends at zero once the transfers are applied. This is the property
  /// that actually matters; the transfer count is only the optimisation.
  void expectSettles(Map<String, double> net, List<Transfer> transfers) {
    for (final person in net.keys) {
      final after =
          net[person]! +
          paidBy(transfers, person) -
          receivedBy(transfers, person);
      expect(after, closeTo(0, 0.011), reason: '$person is not square');
    }
  }

  test('a chain collapses to one payment', () {
    // A owes B, B owes C the same — so A should simply pay C.
    final net = {'A': -500.0, 'B': 0.0, 'C': 500.0};
    final transfers = simplifyDebts(net);
    expect(transfers, [const Transfer('A', 'C', 500)]);
    expectSettles(net, transfers);
  });

  test(
    'three people owing in different directions need two payments, not three',
    () {
      final net = {'A': -800.0, 'B': 300.0, 'C': 500.0};
      final transfers = simplifyDebts(net);
      expect(transfers.length, 2);
      expectSettles(net, transfers);
    },
  );

  test('everyone already square means nobody pays anything', () {
    expect(simplifyDebts({'A': 0.0, 'B': 0.0}), isEmpty);
    expect(simplifyDebts(const {}), isEmpty);
  });

  test('money out always equals money in', () {
    final net = {'A': -1200.0, 'B': -300.0, 'C': 900.0, 'D': 600.0};
    final transfers = simplifyDebts(net);
    final total = transfers.fold(0.0, (sum, t) => sum + t.amount);
    expect(total, closeTo(1500, 0.01));
    expectSettles(net, transfers);
  });

  test('at most one payment fewer than there are people', () {
    final net = {'A': -1000.0, 'B': -500.0, 'C': 700.0, 'D': 500.0, 'E': 300.0};
    final transfers = simplifyDebts(net);
    expect(transfers.length, lessThanOrEqualTo(net.length - 1));
    expectSettles(net, transfers);
  });

  test('sub-paisa residue never becomes a payment of nothing', () {
    final transfers = simplifyDebts({'A': -0.004, 'B': 0.004});
    expect(transfers, isEmpty);
    expect(
      simplifyDebts({'A': -100.0, 'B': 99.999}).every((t) => t.amount > 0.01),
      isTrue,
    );
  });

  test('the pairwise case is exactly what the ledger already shows', () {
    // Documented limitation, asserted so it stays honest: with two people this
    // can only ever return the one number PersonBalance.net already displays.
    final transfers = simplifyDebts({'You': 430.0, 'Rahul': -430.0});
    expect(transfers, [const Transfer('Rahul', 'You', 430)]);
  });
}
