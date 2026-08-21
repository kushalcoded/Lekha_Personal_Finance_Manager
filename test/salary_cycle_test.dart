import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/settings/providers/settings_providers.dart';

void main() {
  group('nextSalaryDayAfter', () {
    test('finds the day later in the same month', () {
      expect(nextSalaryDayAfter(DateTime(2026, 8, 1), 7), DateTime(2026, 8, 7));
    });

    test('rolls to next month when the day has already passed', () {
      expect(nextSalaryDayAfter(DateTime(2026, 8, 7), 7), DateTime(2026, 9, 7));
      expect(
        nextSalaryDayAfter(DateTime(2026, 8, 20), 7),
        DateTime(2026, 9, 7),
      );
    });

    test('clamps to the last day of a short month', () {
      // A salary day of 31 must still land in February, not overflow into
      // March — the classic date bug.
      expect(
        nextSalaryDayAfter(DateTime(2026, 1, 31), 31),
        DateTime(2026, 2, 28),
      );
      expect(
        nextSalaryDayAfter(DateTime(2026, 3, 31), 31),
        DateTime(2026, 4, 30),
      );
    });

    test('handles a December start crossing the year', () {
      expect(
        nextSalaryDayAfter(DateTime(2026, 12, 20), 7),
        DateTime(2027, 1, 7),
      );
    });
  });

  group('cycleRollDue', () {
    SettingsState stateWith({
      required DateTime cycleStart,
      int? salaryDay,
      DateTime? dismissedFor,
    }) => SettingsState(
      isLoading: false,
      salaryCycleStartDate: cycleStart,
      salaryDay: salaryDay,
      cyclePromptDismissedFor: dismissedFor,
    );

    test('never asks when no salary day is set', () {
      final s = stateWith(cycleStart: DateTime(2026, 7, 1));
      expect(s.cycleRollDue(DateTime(2026, 8, 30)), isFalse);
    });

    test('asks once the salary day has arrived', () {
      final s = stateWith(cycleStart: DateTime(2026, 7, 7), salaryDay: 7);
      expect(s.cycleRollDue(DateTime(2026, 8, 6)), isFalse);
      expect(s.cycleRollDue(DateTime(2026, 8, 7)), isTrue);
      // Salary came late — still asking.
      expect(s.cycleRollDue(DateTime(2026, 8, 9)), isTrue);
    });

    test('a stale cycle is overdue immediately', () {
      // Cycle stuck at 1 Jul with salary on the 7th: it should have rolled
      // on 7 Jul, so it asks right away.
      final s = stateWith(cycleStart: DateTime(2026, 7, 1), salaryDay: 7);
      expect(s.expectedCycleRollDate, DateTime(2026, 7, 7));
      expect(s.cycleRollDue(DateTime(2026, 8, 3)), isTrue);
    });

    test('dismissing silences this roll but not the next', () {
      final s = stateWith(
        cycleStart: DateTime(2026, 7, 7),
        salaryDay: 7,
        dismissedFor: DateTime(2026, 8, 7),
      );
      expect(s.cycleRollDue(DateTime(2026, 8, 7)), isFalse);

      // Once the cycle actually moves, the next roll asks again.
      final next = stateWith(
        cycleStart: DateTime(2026, 8, 9),
        salaryDay: 7,
        dismissedFor: DateTime(2026, 8, 7),
      );
      expect(next.expectedCycleRollDate, DateTime(2026, 9, 7));
      expect(next.cycleRollDue(DateTime(2026, 9, 7)), isTrue);
    });
  });
}
