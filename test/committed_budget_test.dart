import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/category/category_kinds.dart';
import 'package:personal_expanse_tracker/models/category/expense_category.dart';
import 'package:personal_expanse_tracker/models/recurring/recurring_expense_template.dart';
import 'package:personal_expanse_tracker/providers/budget/committed_planned.dart';

/// Bills are not taken out of the budget — the budget is the everyday
/// allowance itself. What is still counted is what has yet to leave this
/// cycle, shown beside what has already been paid, so the figure has to be
/// exact about which occurrences fall inside the cycle.
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
}
