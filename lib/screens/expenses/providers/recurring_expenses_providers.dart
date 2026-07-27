import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/expense/expense_model.dart';
import '../../../models/recurring/recurring_expense_template.dart';
import '../../../models/recurring/recurring_notification_hook.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../utils/formatters/formatters.dart';

enum RecurringTemplateFilter { all, due, upcoming, overdue }

class RecurringTemplateUiState {
  final RecurringTemplateFilter filter;

  const RecurringTemplateUiState({this.filter = RecurringTemplateFilter.all});

  RecurringTemplateUiState copyWith({RecurringTemplateFilter? filter}) {
    return RecurringTemplateUiState(filter: filter ?? this.filter);
  }
}

final recurringTemplateUiProvider =
    StateNotifierProvider<
      RecurringTemplateUiNotifier,
      RecurringTemplateUiState
    >((ref) => RecurringTemplateUiNotifier());

class RecurringTemplateUiNotifier
    extends StateNotifier<RecurringTemplateUiState> {
  RecurringTemplateUiNotifier() : super(const RecurringTemplateUiState());

  void setFilter(RecurringTemplateFilter filter) {
    state = state.copyWith(filter: filter);
  }
}

final userRecurringTemplatesProvider =
    Provider.family<List<RecurringExpenseTemplate>, String>((ref, userId) {
      return ref
          .watch(recurringTemplatesProvider)
          .templates
          .where((template) => template.userId == userId && template.isActive)
          .toList()
        ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
    });

final dueRecurringTemplatesProvider =
    Provider.family<List<RecurringExpenseTemplate>, String>((ref, userId) {
      final templates = ref.watch(userRecurringTemplatesProvider(userId));
      final today = _day(DateTime.now());
      return templates.where((template) {
        final due = _day(template.nextDueDate);
        return !due.isAfter(today);
      }).toList();
    });

final upcomingRecurringTemplatesProvider =
    Provider.family<List<RecurringExpenseTemplate>, String>((ref, userId) {
      final templates = ref.watch(userRecurringTemplatesProvider(userId));
      final today = _day(DateTime.now());
      final upcomingLimit = today.add(const Duration(days: 7));
      return templates.where((template) {
        final due = _day(template.nextDueDate);
        return due.isAfter(today) && !due.isAfter(upcomingLimit);
      }).toList();
    });

final overdueRecurringTemplatesProvider =
    Provider.family<List<RecurringExpenseTemplate>, String>((ref, userId) {
      final templates = ref.watch(userRecurringTemplatesProvider(userId));
      final today = _day(DateTime.now());
      return templates.where((template) {
        final due = _day(template.nextDueDate);
        return due.isBefore(today);
      }).toList();
    });

final filteredRecurringTemplatesProvider =
    Provider.family<List<RecurringExpenseTemplate>, String>((ref, userId) {
      final filter = ref.watch(recurringTemplateUiProvider).filter;
      final all = ref.watch(userRecurringTemplatesProvider(userId));
      switch (filter) {
        case RecurringTemplateFilter.due:
          return ref.watch(dueRecurringTemplatesProvider(userId));
        case RecurringTemplateFilter.upcoming:
          return ref.watch(upcomingRecurringTemplatesProvider(userId));
        case RecurringTemplateFilter.overdue:
          return ref.watch(overdueRecurringTemplatesProvider(userId));
        case RecurringTemplateFilter.all:
          return all;
      }
    });

final recurringNotificationHooksProvider =
    Provider.family<List<RecurringNotificationHook>, String>((ref, userId) {
      final templates = ref.watch(userRecurringTemplatesProvider(userId));
      final today = _day(DateTime.now());
      final upcomingLimit = today.add(const Duration(days: 7));
      final hooks = <RecurringNotificationHook>[];

      for (final template in templates) {
        final due = _day(template.nextDueDate);
        if (due.isBefore(today)) {
          hooks.add(
            RecurringNotificationHook(
              templateId: template.id,
              dueAt: due,
              type: RecurringNotificationType.overdue,
              title: '${template.category} overdue',
              message:
                  'Recurring expense was due ${AppFormatters.formatDate(due)}.',
            ),
          );
        } else if (due == today) {
          hooks.add(
            RecurringNotificationHook(
              templateId: template.id,
              dueAt: due,
              type: RecurringNotificationType.dueToday,
              title: '${template.category} due today',
              message: 'Recurring expense is due today.',
            ),
          );
        } else if (!due.isAfter(upcomingLimit)) {
          hooks.add(
            RecurringNotificationHook(
              templateId: template.id,
              dueAt: due,
              type: RecurringNotificationType.upcoming,
              title: '${template.category} upcoming',
              message:
                  'Recurring expense due ${AppFormatters.formatDate(due)}.',
            ),
          );
        }
      }

      hooks.sort((a, b) => a.dueAt.compareTo(b.dueAt));
      return hooks;
    });

final recurringExpenseActionsProvider = Provider<RecurringExpenseActions>((
  ref,
) {
  return RecurringExpenseActions(ref);
});

class RecurringExpenseActions {
  final Ref _ref;

  RecurringExpenseActions(this._ref);

  Future<bool> generateExpenseFromTemplate(
    RecurringExpenseTemplate template,
  ) async {
    final now = DateTime.now();
    if (_alreadyGenerated(template, now)) {
      return false;
    }
    final expense = Expense(
      id: 'rec_${now.microsecondsSinceEpoch}',
      userId: template.userId,
      amount: template.amount,
      category: template.category,
      description: _combinePaymentAndNotes(
        template.paymentMethod,
        template.notes,
      ),
      date: template.nextDueDate,
      recurringTemplateId: template.id,
      recurringDueDate: template.nextDueDate,
      createdAt: now,
      updatedAt: null,
    );
    await _ref.read(expensesProvider.notifier).addExpense(expense);
    final nextDue = _nextDueDate(template.frequency, template.nextDueDate, now);
    await _ref
        .read(recurringTemplatesProvider.notifier)
        .updateTemplate(
          template.id,
          template.copyWith(
            nextDueDate: nextDue,
            lastGeneratedAt: now,
            lastGeneratedExpenseId: expense.id,
            updatedAt: now,
          ),
        );
    return true;
  }

  Future<int> generateDueExpenses(String userId) async {
    final dueTemplates = _ref.read(dueRecurringTemplatesProvider(userId));
    var generated = 0;
    for (final template in dueTemplates) {
      final didGenerate = await generateExpenseFromTemplate(template);
      if (didGenerate) {
        generated += 1;
      }
    }
    return generated;
  }

  String _combinePaymentAndNotes(String paymentMethod, String? notes) {
    final trimmedNotes = notes?.trim();
    if (trimmedNotes == null || trimmedNotes.isEmpty) {
      return paymentMethod;
    }
    return '$paymentMethod - $trimmedNotes';
  }

  bool _alreadyGenerated(RecurringExpenseTemplate template, DateTime now) {
    final expenses = _ref.read(expensesProvider).expenses;
    final dueDate = _day(template.nextDueDate);
    final hasExpense = expenses.any((expense) {
      if (expense.recurringTemplateId != template.id) {
        return false;
      }
      final matchDate = expense.recurringDueDate ?? expense.date;
      return _day(matchDate) == dueDate;
    });

    final generatedAt = template.lastGeneratedAt;
    if (generatedAt != null && _day(generatedAt) == dueDate) {
      return true;
    }
    return hasExpense && !dueDate.isAfter(_day(now));
  }
}

DateTime _nextDueDate(
  RecurringFrequency frequency,
  DateTime currentDueDate,
  DateTime now,
) {
  var next = currentDueDate;
  do {
    next = _advanceDueDate(frequency, next);
  } while (!next.isAfter(now));

  return next;
}

DateTime _advanceDueDate(RecurringFrequency frequency, DateTime from) {
  switch (frequency) {
    case RecurringFrequency.daily:
      return from.add(const Duration(days: 1));
    case RecurringFrequency.weekly:
      return from.add(const Duration(days: 7));
    case RecurringFrequency.monthly:
      return _shiftByMonths(from, 1);
    case RecurringFrequency.yearly:
      return _shiftByMonths(from, 12);
  }
}

DateTime _shiftByMonths(DateTime source, int months) {
  final baseMonthIndex = source.year * 12 + (source.month - 1) + months;
  final targetYear = baseMonthIndex ~/ 12;
  final targetMonth = (baseMonthIndex % 12) + 1;
  final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
  final day = source.day > lastDay ? lastDay : source.day;
  return DateTime(
    targetYear,
    targetMonth,
    day,
    source.hour,
    source.minute,
    source.second,
    source.millisecond,
    source.microsecond,
  );
}

DateTime _day(DateTime input) {
  return DateTime(input.year, input.month, input.day);
}
