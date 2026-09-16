import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/category/category_kinds.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';
import 'package:personal_expanse_tracker/models/recurring/recurring_expense_template.dart';
import 'package:personal_expanse_tracker/providers/budget/committed_planned.dart';

/// The budget now holds money back for bills before saying what is left to
/// spend. Two things have to be exactly right: bills already paid and bills
/// still coming must be added (never max'd), and an occurrence must never be
/// counted on both sides of that sum.
void main() {
  final cycleStart = DateTime(2026, 9, 1);
  final cycleEnd = DateTime(2026, 10, 1);

  final kinds = CategoryKinds.from(const [
    ExpenseCategory(
      name: 'Rent',
      iconKey: 'home',
      colorHex: '#FFFFFF',
      kind: CategoryKind.committed,
    ),
    ExpenseCategory(
      name: 'Electricity',
      iconKey: 'bolt',
      colorHex: '#FFFFFF',
      kind: CategoryKind.committed,
    ),
    ExpenseCategory(name: 'Food', iconKey: 'restaurant', colorHex: '#FFFFFF'),
  ]);

  RecurringExpenseTemplate template({
    required String category,
    required double amount,
    required DateTime nextDue,
    RecurringFrequency frequency = RecurringFrequency.monthly,
  }) => RecurringExpenseTemplate(
    id: '$category-$amount',
    userId: 'u1',
    amount: amount,
    category: category,
    paymentMethod: 'Bank Transfer',
    frequency: frequency,
    nextDueDate: nextDue,
    isActive: true,
    createdAt: cycleStart,
  );

  group('committedPlanned', () {
    test('counts only committed categories', () {
      final planned = committedPlanned(
        activeTemplates: [
          template(
            category: 'Rent',
            amount: 20000,
            nextDue: DateTime(2026, 9, 5),
          ),
          template(
            category: 'Food',
            amount: 3000,
            nextDue: DateTime(2026, 9, 5),
          ),
        ],
        kinds: kinds,
        cycleEnd: cycleEnd,
      );
      expect(planned, 20000);
    });

    test('a bill already generated is no longer planned', () {
      // Generating advances nextDueDate past now, so it falls outside this
      // cycle. That is what makes spent + planned safe to add.
      final planned = committedPlanned(
        activeTemplates: [
          template(
            category: 'Rent',
            amount: 20000,
            nextDue: DateTime(2026, 10, 5),
          ),
        ],
        kinds: kinds,
        cycleEnd: cycleEnd,
      );
      expect(planned, 0);
    });

    test('an overdue bill is still money owed', () {
      // Due before the cycle even started. Dropping it would hand the user an
      // allowance they do not actually have.
      final planned = committedPlanned(
        activeTemplates: [
          template(
            category: 'Rent',
            amount: 20000,
            nextDue: DateTime(2026, 8, 28),
          ),
        ],
        kinds: kinds,
        cycleEnd: cycleEnd,
      );
      expect(planned, 40000, reason: 'the missed one and this cycle\'s');
    });

    test('a weekly bill counts every occurrence in the cycle', () {
      final planned = committedPlanned(
        activeTemplates: [
          template(
            category: 'Electricity',
            amount: 500,
            nextDue: DateTime(2026, 9, 3),
            frequency: RecurringFrequency.weekly,
          ),
        ],
        kinds: kinds,
        cycleEnd: cycleEnd,
      );
      // 3, 10, 17, 24 September.
      expect(planned, 2000);
    });

    test('a yearly bill not due this cycle reserves nothing', () {
      final planned = committedPlanned(
        activeTemplates: [
          template(
            category: 'Rent',
            amount: 12000,
            nextDue: DateTime(2027, 3, 1),
            frequency: RecurringFrequency.yearly,
          ),
        ],
        kinds: kinds,
        cycleEnd: cycleEnd,
      );
      expect(planned, 0);
    });
  });

  group('everydayAllowance', () {
    test('paid bills and coming bills are added, not max-ed', () {
      // The bug this replaced: rent generates and leaves the planned window,
      // so max(spent, planned) returned 20000 and quietly stopped reserving
      // the electricity bill still to come.
      final split = everydayAllowance(
        budget: 50000,
        committedSpent: 20000,
        committedPlanned: 2000,
        everydaySpent: 8000,
      );
      expect(split.committedReserved, 22000);
      expect(split.everydayAllowance, 28000);
      expect(split.everydayLeft, 20000);
      expect(split.isOverCommitted, isFalse);
    });

    test('with no budget set there is no allowance to report', () {
      final split = everydayAllowance(
        budget: 0,
        committedSpent: 20000,
        committedPlanned: 0,
        everydaySpent: 8000,
      );
      expect(split.everydayAllowance, 0);
      expect(split.everydayLeft, 0);
      expect(split.isOverCommitted, isFalse);
    });

    test('bills alone over the budget leave nothing, never a negative', () {
      final split = everydayAllowance(
        budget: 20000,
        committedSpent: 18000,
        committedPlanned: 6000,
        everydaySpent: 1000,
      );
      expect(split.isOverCommitted, isTrue);
      expect(split.everydayAllowance, 0);
      // Everything spent on everyday is over, and says so.
      expect(split.everydayLeft, -1000);
    });

    test('no committed categories leaves the budget exactly as it was', () {
      final split = everydayAllowance(
        budget: 30000,
        committedSpent: 0,
        committedPlanned: 0,
        everydaySpent: 12000,
      );
      expect(split.everydayAllowance, 30000);
      expect(split.everydayLeft, 18000);
    });

    test('landing exactly on budget is not over-committed', () {
      // Two-decimal amounts leave float residue; a paisa of tolerance is what
      // stops "Overspent -₹0" appearing.
      final split = everydayAllowance(
        budget: 10000,
        committedSpent: 9999.999,
        committedPlanned: 0,
        everydaySpent: 0,
      );
      expect(split.isOverCommitted, isFalse);
    });
  });
}
