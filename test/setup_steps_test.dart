import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/dashboard/widgets/setup_checklist_card.dart';
import 'package:personal_expanse_tracker/screens/settings/providers/settings_providers.dart';

/// The checklist is the only thing telling a new account that budgets, salary
/// and a default payment method exist at all — and it must vanish completely
/// for someone already set up, or it nags forever.
void main() {
  List<SetupStep> steps({
    double budget = 20000,
    double salary = 40000,
    int? salaryDay = 7,
    String? defaultPaymentMethod = 'GPay',
    bool seenCategories = true,
    bool seenPeople = true,
  }) => setupSteps(
    budget: budget,
    salary: salary,
    salaryDay: salaryDay,
    defaultPaymentMethod: defaultPaymentMethod,
    seenCategories: seenCategories,
    seenPeople: seenPeople,
  );

  test('a set-up account is asked nothing', () {
    expect(steps(), isEmpty);
  });

  test('a brand new account is asked everything', () {
    expect(
      steps(
        budget: 0,
        salary: 0,
        salaryDay: null,
        defaultPaymentMethod: null,
        seenCategories: false,
        seenPeople: false,
      ),
      SetupStep.values,
    );
  });

  test('setting the budget clears only that step', () {
    expect(steps(budget: 0), [SetupStep.budget]);
    expect(steps(budget: 20000), isEmpty);
  });

  test('a blank default payment method counts as unset', () {
    expect(steps(defaultPaymentMethod: '   '), [SetupStep.paymentMethod]);
  });

  test('the tapped-once rows are independent of the money ones', () {
    expect(steps(seenPeople: false), [SetupStep.people]);
    expect(steps(budget: 0, seenCategories: false), [
      SetupStep.budget,
      SetupStep.categories,
    ]);
  });

  test('every step says what it is and why it matters', () {
    for (final step in SetupStep.values) {
      expect(step.label, isNotEmpty, reason: step.name);
      expect(step.why, isNotEmpty, reason: step.name);
    }
  });

  // Setup offers to move the cycle start onto the salary day; landing on the
  // wrong side of it would re-scope every total on the dashboard.
  group('lastSalaryDayOnOrBefore', () {
    test('this month when the day has already passed', () {
      expect(
        lastSalaryDayOnOrBefore(DateTime(2026, 8, 17), 7),
        DateTime(2026, 8, 7),
      );
    });

    test('today counts as passed', () {
      expect(
        lastSalaryDayOnOrBefore(DateTime(2026, 8, 7), 7),
        DateTime(2026, 8, 7),
      );
    });

    test('last month when it has not', () {
      expect(
        lastSalaryDayOnOrBefore(DateTime(2026, 8, 3), 7),
        DateTime(2026, 7, 7),
      );
    });

    test('a 31st clamps to the length of the month it lands in', () {
      expect(
        lastSalaryDayOnOrBefore(DateTime(2026, 3, 30), 31),
        DateTime(2026, 2, 28),
      );
    });

    test('january steps back into the previous year', () {
      expect(
        lastSalaryDayOnOrBefore(DateTime(2026, 1, 3), 7),
        DateTime(2025, 12, 7),
      );
    });
  });
}
