import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/category_styles.dart';
import '../../models/expense/expense_model.dart';
import '../../models/pending/pending_transaction.dart';
import '../../navigation/floating_glass_nav.dart';
import '../../providers/sms/sms_providers.dart';
import '../../providers/storage/storage_providers.dart';
import '../../providers/sync/sync_providers.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/glass.dart';
import 'providers/expenses_providers.dart';
import 'recurring_screen.dart';
import 'utils/expense_helpers.dart';
import 'widgets/add_expense_modal.dart';
import 'widgets/edit_expense_modal.dart';
import 'widgets/expense_details_sheet.dart';
import 'widgets/expense_filters_sheet.dart';
import 'widgets/expense_section_header.dart';
import 'widgets/expenses_widgets.dart';

/// Expenses — the transaction ledger.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  /// Ids of detected txns picked to merge into one expense. Non-empty = the
  /// Detected section is in selection mode.
  final Set<String> _selectedPending = {};

  /// Desktop master-detail: the expense shown in the right pane.
  String? _selectedExpenseId;

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(expensesListProvider);
    final expensesState = ref.watch(expensesProvider);
    final groupedExpenses = ref.watch(groupedExpensesProvider);
    final categories = ref.watch(expenseCategoriesProvider);
    final stats = ref.watch(expenseStatsProvider);
    final pending = ref.watch(pendingTransactionsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Expenses'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.repeat_rounded),
            tooltip: 'Recurring',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecurringScreen()),
            ),
          ),
          ref.watch(syncProvider.select((s) => s.isSyncing))
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Sync now',
                  onPressed: () => ref.read(syncProvider.notifier).syncNow(),
                ),
          const SizedBox(width: 6),
        ],
      ),
      body: expensesState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _wideWrap(
              isWide,
              expensesState.expenses,
              RefreshIndicator(
                onRefresh: () => ref.read(syncProvider.notifier).syncNow(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _StatBox(
                                    label: 'Spent this cycle',
                                    value: AppFormatters.formatCurrency(
                                      stats.total,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatBox(
                                    label: 'Transactions',
                                    value: '${stats.transactionCount}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            ExpenseSearchBar(
                              onSearch: (query) => ref
                                  .read(expensesListProvider.notifier)
                                  .search(query),
                              onFilterTapped: () => showExpenseFiltersSheet(
                                context,
                                categories: categories,
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: filterState.hasActiveFilters
                                  ? Padding(
                                      key: const ValueKey('active-filters'),
                                      padding: const EdgeInsets.only(top: 12),
                                      child: _ActiveFilters(
                                        filterState: filterState,
                                        notifier: ref.read(
                                          expensesListProvider.notifier,
                                        ),
                                        onClearAll: () => ref
                                            .read(expensesListProvider.notifier)
                                            .clearAllFilters(),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (pending.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _DetectedSection(
                          pending: pending,
                          onAdd: _addFromPending,
                          onDismiss: _dismissPending,
                          selectedIds: _selectedPending,
                          onToggleSelect: _toggleSelectPending,
                          onCancelSelect: _clearPendingSelection,
                          onAddSelected: () => _addSelectedAsOne(pending),
                        ),
                      ),
                    if (groupedExpenses.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: EmptyExpensesState(
                            title: filterState.hasActiveFilters
                                ? 'No expenses match your filters'
                                : 'No expenses yet',
                            message: filterState.hasActiveFilters
                                ? 'Try clearing or adjusting your filters.'
                                : 'Tap + to add your first expense.',
                            primaryLabel: filterState.hasActiveFilters
                                ? 'Clear Filters'
                                : 'Add Expense',
                            onPrimaryPressed: filterState.hasActiveFilters
                                ? () => ref
                                      .read(expensesListProvider.notifier)
                                      .clearAllFilters()
                                : () => showAddExpenseModal(context),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final group = groupedExpenses[index];
                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              index == 0 ? 6 : 18,
                              16,
                              0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ExpenseSectionHeader(
                                  date: group.date,
                                  total: group.total,
                                  count: group.expenses.length,
                                ),
                                const SizedBox(height: 8),
                                ...group.expenses.map(
                                  (expense) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Dismissible(
                                      key: ValueKey(expense.id),
                                      direction: DismissDirection.endToStart,
                                      confirmDismiss: (_) =>
                                          _confirmDelete(expense),
                                      background: const _DismissBackground(),
                                      child: _ExpenseRow(
                                        expense: expense,
                                        onTap: () => _showDetails(expense),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }, childCount: groupedExpenses.length),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: isWide ? 24 : kNavBottomInset),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Desktop: pin the list into a fixed-width master column with the selected
  /// expense in a live detail pane beside it. Narrow screens get [list] as-is.
  Widget _wideWrap(bool isWide, List<Expense> all, Widget list) {
    if (!isWide) return list;
    final matches = all.where((e) => e.id == _selectedExpenseId);
    final selected = matches.isEmpty ? null : matches.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 16, 24),
            child: selected == null
                ? GlassCard(
                    radius: 18,
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'Select an expense to see its details',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : GlassCard(
                    radius: 18,
                    padding: EdgeInsets.zero,
                    child: ExpenseDetailsContent(
                      inline: true,
                      expense: selected,
                      onEdit: () =>
                          showEditExpenseModal(context, expense: selected),
                      onDelete: () => _confirmDelete(selected),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _addFromPending(PendingTransaction txn) {
    showAddExpenseModal(
      context,
      initialAmount: txn.amount,
      initialDate: txn.dateTime,
      onSaved: (expense) => ref
          .read(pendingTransactionsProvider.notifier)
          .markAdded(txn.id, expense.id),
    );
  }

  void _dismissPending(PendingTransaction txn) {
    ref.read(pendingTransactionsProvider.notifier).dismiss(txn.id);
  }

  void _toggleSelectPending(PendingTransaction txn) {
    setState(() {
      if (!_selectedPending.remove(txn.id)) _selectedPending.add(txn.id);
    });
  }

  void _clearPendingSelection() => setState(_selectedPending.clear);

  /// Merge the selected detected txns into one expense: amount = sum, date =
  /// latest. The Add Expense modal opens prefilled; on save, every merged
  /// pending is marked added and linked to that one expense.
  void _addSelectedAsOne(List<PendingTransaction> pending) {
    final chosen = pending
        .where((t) => _selectedPending.contains(t.id))
        .toList();
    if (chosen.isEmpty) return;
    final total = chosen.fold<double>(0, (sum, t) => sum + t.amount);
    final latest = chosen
        .map((t) => t.dateTime)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final ids = chosen.map((t) => t.id).toList();
    showAddExpenseModal(
      context,
      initialAmount: total,
      initialDate: latest,
      onSaved: (expense) {
        final notifier = ref.read(pendingTransactionsProvider.notifier);
        for (final id in ids) {
          notifier.markAdded(id, expense.id);
        }
      },
    );
    _clearPendingSelection();
  }

  void _showDetails(Expense expense) {
    // Desktop: select into the detail pane instead of opening a sheet.
    if (MediaQuery.sizeOf(context).width >= kWideBreakpoint) {
      setState(() => _selectedExpenseId = expense.id);
      return;
    }
    showExpenseDetailsSheet(
      context: context,
      expense: expense,
      onEdit: () => showEditExpenseModal(context, expense: expense),
      onDelete: () => _confirmDelete(expense),
    );
  }

  Future<bool> _confirmDelete(Expense expense) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _deleteExpenseWithUndo(expense);
      return true;
    }
    return false;
  }

  void _deleteExpenseWithUndo(Expense expense) {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(expensesProvider.notifier).deleteExpense(expense.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Expense deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            ref.read(expensesProvider.notifier).addExpense(expense);
          },
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassCard(
      radius: 14,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback onTap;

  const _ExpenseRow({required this.expense, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = CategoryStyles.of(expense.category);
    final method =
        expense.paymentMethod ?? inferPaymentMethod(expense.description);
    final subtitle = method == null
        ? expense.category
        : '${expense.category} · $method';

    return GlassCard(
      onTap: onTap,
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(style.icon, size: 17, color: style.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description ?? expense.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '-${AppFormatters.formatCurrency(expense.amount)}',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerRight,
      child: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
    );
  }
}

/// SMS-detected debits awaiting the user's decision.
class _DetectedSection extends StatelessWidget {
  final List<PendingTransaction> pending;
  final void Function(PendingTransaction) onAdd;
  final void Function(PendingTransaction) onDismiss;
  final Set<String> selectedIds;
  final void Function(PendingTransaction) onToggleSelect;
  final VoidCallback onCancelSelect;
  final VoidCallback onAddSelected;

  const _DetectedSection({
    required this.pending,
    required this.onAdd,
    required this.onDismiss,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onCancelSelect,
    required this.onAddSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectMode = selectedIds.isNotEmpty;
    final chosen = pending.where((t) => selectedIds.contains(t.id));
    final selectedTotal = chosen.fold<double>(0, (sum, t) => sum + t.amount);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sms_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 7),
              Text(
                'Detected',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${pending.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            selectMode
                ? 'Tap cards to pick which to merge into one expense.'
                : 'From your bank SMS — add, or long-press to merge several.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          ...pending.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DetectedCard(
                txn: t,
                onAdd: () => onAdd(t),
                onDismiss: () => onDismiss(t),
                selectMode: selectMode,
                selected: selectedIds.contains(t.id),
                onToggleSelect: () => onToggleSelect(t),
              ),
            ),
          ),
          if (selectMode)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAddSelected,
                    icon: const Icon(Icons.merge_rounded, size: 18),
                    label: Text(
                      'Add ${selectedIds.length} as one · '
                      '${AppFormatters.formatCurrency(selectedTotal)}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onCancelSelect,
                  child: const Text('Cancel'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DetectedCard extends StatelessWidget {
  final PendingTransaction txn;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;
  final bool selectMode;
  final bool selected;
  final VoidCallback onToggleSelect;

  const _DetectedCard({
    required this.txn,
    required this.onAdd,
    required this.onDismiss,
    this.selectMode = false,
    this.selected = false,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final when = DateFormat('MMM d · h:mm a').format(txn.dateTime);

    return GestureDetector(
      onLongPress: onToggleSelect,
      onTap: selectMode ? onToggleSelect : null,
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.primary.withValues(alpha: 0.16),
            const Color(0xFF1E1B28).withValues(alpha: 0.42),
          ],
        ),
        border: Border.all(
          color: cs.primary.withValues(alpha: selected ? 0.85 : 0.28),
          width: selected ? 1.6 : 1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    selectMode
                        ? (selected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined)
                        : Icons.south_west_rounded,
                    size: 17,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '-${AppFormatters.formatCurrency(txn.amount)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '$when · from SMS',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              txn.rawBody,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (!selectMode)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: onAdd, child: const Text('Add')),
                ],
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  final ExpensesListState filterState;
  final ExpensesListNotifier notifier;
  final VoidCallback onClearAll;

  const _ActiveFilters({
    required this.filterState,
    required this.notifier,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      ...filterState.selectedFilters.map(
        (category) => CategoryFilterChip(
          label: category,
          isSelected: true,
          onSelected: () => notifier.filterByCategory(category),
        ),
      ),
    ];

    if (filterState.dateRange != null) {
      final range = filterState.dateRange!;
      final startLabel = AppFormatters.formatDate(
        range.start,
        format: 'MMM dd',
      );
      final endLabel = AppFormatters.formatDate(range.end, format: 'MMM dd');
      chips.add(
        Chip(
          label: Text('Date: $startLabel - $endLabel'),
          onDeleted: () => notifier.setDateRange(null),
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
        TextButton(onPressed: onClearAll, child: const Text('Clear')),
      ],
    );
  }
}
