import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/recurring/recurring_expense_template.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/storage/storage_providers.dart';
import '../settings/providers/settings_providers.dart';
import 'providers/recurring_expenses_providers.dart';
import 'widgets/recurring_expense_modal.dart';
import 'widgets/recurring_expense_widgets.dart';

/// Manage recurring expense templates (moved off the Expenses list).
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final uiState = ref.watch(recurringTemplateUiProvider);
    final templates = ref.watch(filteredRecurringTemplatesProvider(userId));
    final dueTemplates = ref.watch(dueRecurringTemplatesProvider(userId));
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Recurring'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New template',
            onPressed: () => showRecurringExpenseModal(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          RecurringTemplateFilterBar(
            selected: uiState.filter,
            onChange: (filter) => ref
                .read(recurringTemplateUiProvider.notifier)
                .setFilter(filter),
          ),
          const SizedBox(height: 12),
          if (templates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No recurring templates in this view.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...templates.map((template) {
              final now = DateTime.now();
              final isOverdue = DateTime(
                template.nextDueDate.year,
                template.nextDueDate.month,
                template.nextDueDate.day,
              ).isBefore(DateTime(now.year, now.month, now.day));
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RecurringTemplateCard(
                  template: template,
                  isDue: dueTemplates.any((item) => item.id == template.id),
                  isOverdue: isOverdue,
                  onGenerate: () => _generate(
                    context,
                    ref,
                    template,
                    settings.recurringQuickGenerateEnabled,
                  ),
                  onEdit: () =>
                      showRecurringExpenseModal(context, template: template),
                  onDelete: () => _confirmDelete(context, ref, template),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _generate(
    BuildContext context,
    WidgetRef ref,
    RecurringExpenseTemplate template,
    bool enabled,
  ) async {
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recurring quick-generate is disabled in settings.'),
        ),
      );
      return;
    }
    await ref
        .read(recurringExpenseActionsProvider)
        .generateExpenseFromTemplate(template);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generated ${template.category} expense')),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    RecurringExpenseTemplate template,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recurring template?'),
        content: const Text('This template will no longer generate expenses.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(recurringTemplatesProvider.notifier)
        .deleteTemplate(template.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Recurring template deleted')));
  }
}
