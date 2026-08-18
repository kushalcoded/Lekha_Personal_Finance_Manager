import '../../../utils/amount_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/expense/expense_model.dart';
import '../../../providers/payment/payment_method_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/form_bits.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/expenses_providers.dart';
import '../utils/expense_helpers.dart';
import '../utils/split_helpers.dart';
import '../utils/split_persistence.dart';
import 'split_sheet.dart';
import 'amount_input.dart';
import 'category_selector.dart';
import 'expense_date_picker.dart';
import 'payment_method_selector.dart';
import 'expense_notes_field.dart';
import 'save_expense_button.dart';

Future<void> showEditExpenseModal(
  BuildContext context, {
  required Expense expense,
}) {
  final isDesktop = MediaQuery.of(context).size.width >= 900;

  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: EditExpenseForm(expense: expense, isDialog: true),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: EditExpenseForm(expense: expense, isDialog: false),
        ),
      );
    },
  );
}

class EditExpenseForm extends ConsumerStatefulWidget {
  final Expense expense;
  final bool isDialog;

  const EditExpenseForm({
    super.key,
    required this.expense,
    required this.isDialog,
  });

  @override
  ConsumerState<EditExpenseForm> createState() => _EditExpenseFormState();
}

class _EditExpenseFormState extends ConsumerState<EditExpenseForm> {
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  String? _selectedCategory;
  String? _selectedPaymentMethod;
  DateTime _selectedDate = DateTime.now();
  bool _showValidation = false;
  SplitConfig _split = const SplitConfig();
  SplitLinks? _links;
  bool _splitDirty = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.expense.amount.toStringAsFixed(2),
    );
    _notesController = TextEditingController(
      text: widget.expense.description ?? '',
    );
    _selectedCategory = widget.expense.category;
    _selectedPaymentMethod =
        widget.expense.paymentMethod ??
        inferPaymentMethod(widget.expense.description);
    _selectedDate = widget.expense.date;
    // Reconstruct an existing split (only possible when you paid) so it can
    // be re-edited; the amount field then shows the full bill.
    _links = findSplitLinks(ref, widget.expense.id);
    final recon = reconstructSplit(_links!, widget.expense.amount);
    if (recon != null) {
      _split = recon.config;
      _amountController.text = recon.total.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isAmountValid {
    final text = _amountController.text.trim();
    final value = parseAmountExpression(text);
    return value != null && value > 0;
  }

  bool get _isFormValid {
    return _isAmountValid && _selectedCategory != null;
  }

  void _markInteracted() {
    if (!_showValidation) {
      setState(() => _showValidation = true);
    }
  }

  /// Picking a pill means the typing is over, so drop the keyboard. The pill's
  /// own InkWell swallows the sheet's tap-to-dismiss, and this can't live in
  /// [_markInteracted] — the amount field calls that on every keystroke.
  void _chose(VoidCallback change) {
    FocusScope.of(context).unfocus();
    _markInteracted();
    setState(change);
  }

  double get _total =>
      parseAmountExpression(_amountController.text.trim()) ?? 0;

  SplitResult get _splitResult => computeSplit(
    total: _total,
    people: _split.people,
    mode: _split.mode,
    exactAmounts: _split.exact,
  );

  Future<void> _openSplit() async {
    if (_total <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter the amount first')));
      return;
    }
    final result = await showSplitSheet(
      context,
      total: _total,
      initial: _split,
    );
    if (result != null && mounted) {
      setState(() {
        _split = result;
        _splitDirty = true;
      });
    }
  }

  /// Note kept in sync: strip any earlier auto "Split ..." marker, re-append the
  /// current one, so editing never stacks markers or leaves a stale total.
  String? _editNote(double total) {
    var typed = _notesController.text.trim();
    typed = typed
        .replaceAll(RegExp(r'\s*·?\s*Split ₹[\d,]+(\.\d+)?$'), '')
        .trim();
    if (!_split.isActive) return typed.isEmpty ? null : typed;
    final amount = AppFormatters.formatCurrency(total);
    return typed.isEmpty ? 'Split $amount' : '$typed · Split $amount';
  }

  Widget _splitSection() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Friend-paid splits saved before participants were recorded know only the
    // payer, so there is nothing to rebuild an editable split from. Newer ones
    // reconstruct like any other and fall through to the editor below.
    if (_links != null &&
        _links!.payable != null &&
        !_links!.paidByMe &&
        _links!.payable!.participants.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.call_split_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Split — you owe ${_links!.payable!.toPerson}. Remove and re-add to change it.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final active = _split.isActive;
    final r = active ? _splitResult : null;
    return InkWell(
      onTap: _openSplit,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active
              ? cs.primary.withValues(alpha: 0.10)
              : cs.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? cs.primary.withValues(alpha: 0.28)
                : cs.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.call_split_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active
                        ? 'Split with ${_split.people.join(', ')}'
                        : 'Split this bill',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (r != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Your share ${AppFormatters.formatCurrency(r.myShare)} · ${AppFormatters.formatCurrency(r.othersTotal)} to receivables',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              active ? Icons.edit_rounded : Icons.chevron_right_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _handleSave() async {
    if (!_isFormValid) {
      setState(() => _showValidation = true);
      return;
    }

    final total = _total;
    final split = _split.isActive ? _splitResult : null;
    final newAmount = split?.myShare ?? total;
    final note = _editNote(total);
    final links = _links;

    // Rewriting a split whose debt is already settled erases real history.
    if (_splitDirty && links != null && links.anySettled) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rewrite this split?'),
          content: const Text(
            'A settlement was already recorded on this split. Saving will '
            'remove it and recreate the debts.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Rewrite'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    if (!mounted) return;

    final updated = widget.expense.copyWith(
      amount: newAmount,
      category: _selectedCategory,
      description: note,
      date: _selectedDate,
      paymentMethod: _selectedPaymentMethod,
      updatedAt: DateTime.now(),
    );

    try {
      await ref
          .read(expensesProvider.notifier)
          .updateExpense(widget.expense.id, updated);
      if (_splitDirty) {
        if (links != null && !links.isEmpty) await deleteSplitLinks(ref, links);
        if (split != null) {
          await createSplitDebts(
            ref: ref,
            userId: widget.expense.userId,
            sourceExpenseId: widget.expense.id,
            config: _split,
            split: split,
            note: note,
            date: _selectedDate,
            category: _selectedCategory!,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense updated successfully'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating expense: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      // Save sits outside the scroll view: the sheet is already lifted by the
      // keyboard inset, so a pinned footer lands right above the keys.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                widget.isDialog ? 20 : 12,
                20,
                8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!widget.isDialog)
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.outline.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Expense',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Update the details of this transaction',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isTwoColumn = constraints.maxWidth >= 520;
                      final amountField = AmountInput(
                        controller: _amountController,
                        onChanged: (_) {
                          _markInteracted();
                          if (_split.isActive) _splitDirty = true;
                          setState(() {});
                        },
                        showError: _showValidation && !_isAmountValid,
                      );
                      final dateField = ExpenseDatePicker(
                        selectedDate: _selectedDate,
                        onChanged: (date) {
                          _markInteracted();
                          setState(() => _selectedDate = date);
                        },
                      );

                      if (isTwoColumn) {
                        return Row(
                          children: [
                            Expanded(child: amountField),
                            const SizedBox(width: 12),
                            Expanded(child: dateField),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          amountField,
                          const SizedBox(height: 12),
                          dateField,
                        ],
                      );
                    },
                  ),
                  // Moving a date before the cycle start hides the expense from the
                  // list, which reads as "my edit deleted it".
                  if (OutOfCycleNote.applies(
                    _selectedDate,
                    ref.watch(
                      settingsProvider.select((s) => s.currentCycleStartDate),
                    ),
                  )) ...[
                    const SizedBox(height: 10),
                    OutOfCycleNote(
                      date: _selectedDate,
                      onUseToday: () {
                        _markInteracted();
                        setState(() => _selectedDate = DateTime.now());
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  CategorySelector(
                    categories: ref.watch(orderedCategoriesProvider).all,
                    selectedCategory: _selectedCategory,
                    onSelected: (value) =>
                        _chose(() => _selectedCategory = value),
                    showError: _showValidation && _selectedCategory == null,
                  ),
                  const SizedBox(height: 16),
                  PaymentMethodSelector(
                    methods: methodsIncluding(
                      ref.watch(paymentMethodsProvider),
                      _selectedPaymentMethod,
                    ),
                    selectedMethod: _selectedPaymentMethod,
                    onSelected: (value) =>
                        _chose(() => _selectedPaymentMethod = value),
                    showError: false,
                  ),
                  const SizedBox(height: 16),
                  _splitSection(),
                  const SizedBox(height: 16),
                  ExpenseNotesField(
                    controller: _notesController,
                    onChanged: (_) => _markInteracted(),
                  ),
                ],
              ),
            ),
          ),
          _footer(colorScheme),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        // Opaque, or the form scrolls through it.
        color: cs.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: widget.isDialog
          ? Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SaveExpenseButton(
                    label: 'Save Changes',
                    onPressed: _handleSave,
                    isEnabled: _isFormValid,
                  ),
                ),
              ],
            )
          : SaveExpenseButton(
              label: 'Save Changes',
              onPressed: _handleSave,
              isEnabled: _isFormValid,
            ),
    );
  }
}
