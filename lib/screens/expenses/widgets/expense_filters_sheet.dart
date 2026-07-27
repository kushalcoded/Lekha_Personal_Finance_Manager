import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../utils/formatters/formatters.dart';
import '../providers/expenses_providers.dart';
import 'expenses_widgets.dart';

Future<void> showExpenseFiltersSheet(
  BuildContext context, {
  required List<String> categories,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: ExpenseFiltersSheet(categories: categories),
    ),
  );
}

class ExpenseFiltersSheet extends ConsumerStatefulWidget {
  final List<String> categories;

  const ExpenseFiltersSheet({super.key, required this.categories});

  @override
  ConsumerState<ExpenseFiltersSheet> createState() =>
      _ExpenseFiltersSheetState();
}

class _ExpenseFiltersSheetState extends ConsumerState<ExpenseFiltersSheet> {
  late DateTimeRange? _selectedRange;
  late String _sortBy;
  late Set<String> _selectedCategories;
  late TextEditingController _minController;
  late TextEditingController _maxController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(expensesListProvider);
    _selectedRange = state.dateRange;
    _sortBy = state.sortBy;
    _selectedCategories = state.selectedFilters.toSet();
    _minController = TextEditingController(
      text: state.minAmount?.toStringAsFixed(2) ?? '',
    );
    _maxController = TextEditingController(
      text: state.maxAmount?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filters & Sorting',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Categories',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.categories.map((category) {
                final isSelected = _selectedCategories.contains(category);
                return CategoryFilterChip(
                  label: category,
                  isSelected: isSelected,
                  onSelected: () {
                    setState(() {
                      if (isSelected) {
                        _selectedCategories.remove(category);
                      } else {
                        _selectedCategories.add(category);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              'Date range',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(DateTime.now().year - 5),
                  lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                  initialDateRange: _selectedRange,
                );
                if (range != null) {
                  setState(() => _selectedRange = range);
                }
              },
              icon: const Icon(Icons.date_range_rounded, size: 18),
              label: Text(
                _selectedRange == null
                    ? 'Select range'
                    : _rangeLabel(_selectedRange!),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Amount range',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Min',
                      prefixText: CurrencyConstants.currencySymbol,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Max',
                      prefixText: CurrencyConstants.currencySymbol,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Sort by',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SortChip(
                  label: 'Newest',
                  isSelected: _sortBy == 'newest',
                  onSelected: () => setState(() => _sortBy = 'newest'),
                ),
                _SortChip(
                  label: 'Oldest',
                  isSelected: _sortBy == 'oldest',
                  onSelected: () => setState(() => _sortBy = 'oldest'),
                ),
                _SortChip(
                  label: 'Highest',
                  isSelected: _sortBy == 'highest',
                  onSelected: () => setState(() => _sortBy = 'highest'),
                ),
                _SortChip(
                  label: 'Lowest',
                  isSelected: _sortBy == 'lowest',
                  onSelected: () => setState(() => _sortBy = 'lowest'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                TextButton(onPressed: _handleClear, child: const Text('Clear')),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _handleApply,
                    child: const Text('Apply Filters'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleApply() {
    final minAmount = double.tryParse(_minController.text.trim());
    final maxAmount = double.tryParse(_maxController.text.trim());
    final notifier = ref.read(expensesListProvider.notifier);

    notifier.setCategories(_selectedCategories.toList());
    notifier.setDateRange(_selectedRange);
    notifier.setAmountRange(minAmount, maxAmount);
    notifier.setSortBy(_sortBy);

    Navigator.of(context).pop();
  }

  String _rangeLabel(DateTimeRange range) {
    final startLabel = AppFormatters.formatDate(range.start, format: 'MMM dd');
    final endLabel = AppFormatters.formatDate(range.end, format: 'MMM dd');
    return '$startLabel - $endLabel';
  }

  void _handleClear() {
    setState(() {
      _selectedRange = null;
      _sortBy = 'newest';
      _selectedCategories.clear();
      _minController.clear();
      _maxController.clear();
    });
    ref.read(expensesListProvider.notifier).clearAllFilters();
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _SortChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: isSelected ? colorScheme.primary : colorScheme.onSurface,
      ),
      selectedColor: colorScheme.primary.withValues(alpha: 0.18),
      backgroundColor: colorScheme.surface,
      side: BorderSide(
        color: isSelected
            ? colorScheme.primary
            : colorScheme.outline.withValues(alpha: 0.3),
      ),
    );
  }
}
