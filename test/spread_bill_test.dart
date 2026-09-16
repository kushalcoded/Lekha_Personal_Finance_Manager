import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/category/category_kinds.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';
import 'package:personal_expanse_tracker/models/recurring/recurring_expense_template.dart';
import 'package:personal_expanse_tracker/providers/budget/committed_planned.dart';

/// A yearly insurance premium lands in one cycle and wrecks it, even though it
/// was known about all year. Spreading holds back a share every cycle and lets
/// the real payment draw only that share from the allowance.
void main() {
  final cycleEnd = DateTime(2026, 10, 1);

  final kinds = CategoryKinds.from(const [
    ExpenseCategory(
      name: 'Insurance',
      iconKey: 'shield',
      colorHex: '#FFFFFF',
      kind: CategoryKind.committed,
    ),
    ExpenseCategory(
      name: 'Rent',
      iconKey: 'home',
      colorHex: '#FFFFFF',
      kind: CategoryKind.committed,
    ),
  ]);

  RecurringExpenseTemplate yearly({
    required double amount,
    required int spread,
    required DateTime nextDue,
  }) => RecurringExpenseTemplate(
    id: 'insurance',
    userId: 'u1',
    amount: amount,
    category: 'Insurance',
    paymentMethod: 'Bank Transfer',
    frequency: RecurringFrequency.yearly,
    nextDueDate: nextDue,
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    spreadOverCycles: spread,
  );

  test('a spread bill reserves its share even when it is months away', () {
    final planned = committedPlanned(
      activeTemplates: [
        yearly(amount: 12000, spread: 12, nextDue: DateTime(2027, 3, 1)),
      ],
      kinds: kinds,
      cycleEnd: cycleEnd,
    );
    expect(planned, 1000);
  });

  test('without spreading it reserves nothing until the cycle it lands in', () {
    final planned = committedPlanned(
      activeTemplates: [
        yearly(amount: 12000, spread: 1, nextDue: DateTime(2027, 3, 1)),
      ],
      kinds: kinds,
      cycleEnd: cycleEnd,
    );
    expect(planned, 0);
  });

  test('the cycle it is paid draws only the share, not the lump', () {
    // ₹12,000 actually left, and it is in committedSpent. But a share was held
    // back every cycle, so the allowance loses ₹1,000, not ₹12,000.
    final split = everydayAllowance(
      budget: 50000,
      committedSpent: 12000,
      committedPlanned: 1000,
      everydaySpent: 5000,
      spreadPaid: 12000,
    );
    expect(split.committedReserved, 1000);
    expect(split.everydayAllowance, 49000);
    expect(split.everydayLeft, 44000);
  });

  test('a spread bill does not hide an ordinary bill paid the same cycle', () {
    final split = everydayAllowance(
      budget: 50000,
      committedSpent: 32000, // insurance 12,000 + rent 20,000
      committedPlanned: 1000,
      everydaySpent: 0,
      spreadPaid: 12000,
    );
    expect(split.committedReserved, 21000);
  });

  test('cycleShare is the amount itself when nothing is spread', () {
    final template = yearly(
      amount: 12000,
      spread: 1,
      nextDue: DateTime(2026, 9, 10),
    );
    expect(template.isSpread, isFalse);
    expect(template.cycleShare, 12000);
  });

  test('a template saved before spreading existed reads as not spread', () {
    final json = yearly(
      amount: 12000,
      spread: 6,
      nextDue: DateTime(2026, 9, 10),
    ).toJson()..remove('spreadOverCycles');
    expect(RecurringExpenseTemplate.fromJson(json).spreadOverCycles, 1);
  });
}
