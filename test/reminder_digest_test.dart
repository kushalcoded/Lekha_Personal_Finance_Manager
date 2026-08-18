import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/models/reminder/reminder_model.dart';
import 'package:personal_expanse_tracker/screens/settings/providers/reminder_providers.dart';

/// The daily notification is one line. Getting it wrong means either waking
/// someone for nothing or burying the thing that mattered.
void main() {
  AppReminder reminder(String message, ReminderSeverity severity) =>
      AppReminder(
        id: message,
        type: ReminderType.overdueReceivable,
        title: 'Overdue receivables',
        message: message,
        dueAt: DateTime(2026, 8, 17),
        severity: severity,
      );

  test('nothing to say means no notification at all', () {
    expect(reminderDigest(const []), isNull);
  });

  test('one reminder speaks for itself', () {
    final digest = reminderDigest([
      reminder('3 receivables are overdue.', ReminderSeverity.warning),
    ]);

    expect(digest!.title, 'Overdue receivables');
    expect(digest.body, '3 receivables are overdue.');
  });

  test('the rest become a count behind the most severe one', () {
    final digest = reminderDigest([
      reminder('3 receivables are overdue.', ReminderSeverity.danger),
      reminder('2 recurring templates are past due.', ReminderSeverity.info),
      reminder('Review your budget.', ReminderSeverity.info),
    ]);

    expect(digest!.body, '3 receivables are overdue. · 2 more');
  });
}
