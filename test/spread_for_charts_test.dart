import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/expense/expense_model.dart';
import 'package:personal_expanse_tracker/providers/spread/spread_providers.dart';

/// A spread payment is drawn by Insights as one slice a month. The record is
/// untouched — these tests pin the slicing, because a total that stops adding
/// up, or a future month that leaks into today's figure, would both be silent.
void main() {
  Expense expense(
    double amount,
    DateTime date, {
    String id = 'insurance',
    String category = 'Insurance',
  }) => Expense(
    id: id,
    userId: 'u1',
    amount: amount,
    category: category,
    date: date,
    createdAt: date,
  );

  double total(Iterable<Expense> e) => e.fold(0.0, (s, x) => s + x.amount);

  test('an expense that is not spread passes through unchanged', () {
    final e = expense(12000, DateTime(2026, 3, 5));
    final out = spreadForCharts([e], const {}, now: DateTime(2026, 9, 16));
    expect(out.single, same(e));
  });

  test('one month is the same as not spreading', () {
    final e = expense(12000, DateTime(2026, 3, 5));
    final out = spreadForCharts(
      [e],
      {'insurance': 1},
      now: DateTime(2026, 9, 16),
    );
    expect(out.single, same(e));
  });

  test('a year paid eleven months ago is twelve monthly slices', () {
    final out = spreadForCharts(
      [expense(12000, DateTime(2025, 10, 5))],
      {'insurance': 12},
      now: DateTime(2026, 9, 16),
    ).toList();
    expect(out, hasLength(12));
    expect(out.every((s) => s.amount == 1000), isTrue);
    expect(out.first.date, DateTime(2025, 10, 5));
    expect(out.last.date, DateTime(2026, 9, 5));
    expect(out.every((s) => s.category == 'Insurance'), isTrue);
  });

  test('slices always add back up to what was paid', () {
    final out = spreadForCharts(
      [expense(1000, DateTime(2026, 1, 5))],
      {'insurance': 3},
      now: DateTime(2026, 9, 16),
    ).toList();
    expect(out.map((s) => s.amount), [333.33, 333.33, closeTo(333.34, 1e-9)]);
    expect(total(out), closeTo(1000, 1e-9));
  });

  test('nothing from the future lands in today', () {
    // Every Insights window is a lower bound only. Without this, all twelve
    // slices of a payment made today would count in this cycle.
    final out = spreadForCharts(
      [expense(12000, DateTime(2026, 9, 16))],
      {'insurance': 12},
      now: DateTime(2026, 9, 16, 18),
    ).toList();
    expect(out, hasLength(1));
    expect(out.single.amount, 1000);
  });

  test('a payment on the 31st stays on the last day of each month', () {
    // Shifting from the slice before would compound the clamp and drift to
    // Mar 28.
    final out = spreadForCharts(
      [expense(900, DateTime(2026, 1, 31))],
      {'insurance': 3},
      now: DateTime(2026, 9, 16),
    ).toList();
    expect(out.map((s) => s.date), [
      DateTime(2026, 1, 31),
      DateTime(2026, 2, 28),
      DateTime(2026, 3, 31),
    ]);
  });

  test('a leap year gives February its 29th', () {
    final out = spreadForCharts(
      [expense(600, DateTime(2028, 1, 31))],
      {'insurance': 2},
      now: DateTime(2028, 9, 1),
    ).toList();
    expect(out.last.date, DateTime(2028, 2, 29));
  });

  test('a refund spreads by the same rule', () {
    final out = spreadForCharts(
      [expense(-600, DateTime(2026, 1, 5), id: 'refund')],
      {'refund': 3},
      now: DateTime(2026, 9, 16),
    ).toList();
    expect(out.map((s) => s.amount), [-200, -200, closeTo(-200, 1e-9)]);
  });

  test('an entry for an expense that no longer exists changes nothing', () {
    final e = expense(500, DateTime(2026, 9, 1), id: 'tea');
    final out = spreadForCharts(
      [e],
      {'deleted-long-ago': 12},
      now: DateTime(2026, 9, 16),
    );
    expect(out.single, same(e));
  });

  test('slices get their own ids so no two collide', () {
    final out = spreadForCharts(
      [expense(300, DateTime(2026, 1, 5))],
      {'insurance': 3},
      now: DateTime(2026, 9, 16),
    ).toList();
    expect(out.map((s) => s.id).toSet(), hasLength(3));
  });
}
