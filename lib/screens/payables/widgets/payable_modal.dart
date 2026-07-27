import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/payable/payable_model.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../expenses/providers/expenses_providers.dart';
import '../../expenses/widgets/amount_input.dart';
import '../../expenses/widgets/category_selector.dart';
import '../../expenses/widgets/expense_date_picker.dart';
import '../../expenses/widgets/expense_notes_field.dart';
import '../../expenses/widgets/save_expense_button.dart';

Future<void> showAddPayableModal(BuildContext context) {
  return _showPayableModal(
    context,
    child: const PayableForm(isDialog: false),
    dialogChild: const PayableForm(isDialog: true),
  );
}

Future<void> showEditPayableModal(
  BuildContext context, {
  required Payable payable,
}) {
  return _showPayableModal(
    context,
    child: PayableForm(payable: payable, isDialog: false),
    dialogChild: PayableForm(payable: payable, isDialog: true),
  );
}

Future<void> _showPayableModal(
  BuildContext context, {
  required Widget child,
  required Widget dialogChild,
}) {
  return showResponsiveSheet(
    context,
    mobileChild: child,
    desktopChild: dialogChild,
  );
}

class PayableForm extends ConsumerStatefulWidget {
  final Payable? payable;
  final bool isDialog;

  const PayableForm({super.key, this.payable, required this.isDialog});

  @override
  ConsumerState<PayableForm> createState() => _PayableFormState();
}

class _PayableFormState extends ConsumerState<PayableForm> {
  late final TextEditingController _personController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  String? _selectedCategory;
  late DateTime _dueDate;
  bool _showValidation = false;

  bool get _isEditing => widget.payable != null;

  @override
  void initState() {
    super.initState();
    final payable = widget.payable;
    _personController = TextEditingController(text: payable?.toPerson ?? '');
    _amountController = TextEditingController(
      text: payable == null ? '' : payable.amount.toStringAsFixed(2),
    );
    _notesController = TextEditingController(text: payable?.notes ?? '');
    _selectedCategory = payable?.category;
    _dueDate = payable?.dueDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _personController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isPersonValid => _personController.text.trim().isNotEmpty;

  bool get _isAmountValid {
    final value = double.tryParse(_amountController.text.trim());
    return value != null && value > 0;
  }

  bool get _isFormValid {
    return _isPersonValid && _isAmountValid && _selectedCategory != null;
  }

  void _markInteracted() {
    if (!_showValidation) {
      setState(() => _showValidation = true);
    }
  }

  Future<void> _handleSave() async {
    if (!_isFormValid) {
      setState(() => _showValidation = true);
      return;
    }

    final now = DateTime.now();
    final existing = widget.payable;
    final userId = ref.read(currentUserIdProvider) ?? localUserId;
    final amount = double.parse(_amountController.text.trim());
    final paidAmount = existing == null
        ? 0.0
        : (existing.amount - existing.remainingAmount).clamp(0.0, amount);
    final remainingAmount = (amount - paidAmount).clamp(0.0, amount);
    final status = remainingAmount <= 0
        ? PayableStatus.paid
        : (remainingAmount < amount
              ? PayableStatus.partial
              : PayableStatus.pending);

    final next = Payable(
      id: existing?.id ?? const Uuid().v4(),
      userId: existing?.userId ?? userId,
      toPerson: _personController.text.trim(),
      amount: amount,
      remainingAmount: remainingAmount,
      category: _selectedCategory!,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: existing?.createdAt ?? now,
      dueDate: _dueDate,
      status: status,
      settlements: existing?.settlements ?? const [],
      updatedAt: _isEditing ? now : null,
    );

    try {
      if (_isEditing) {
        await ref.read(payablesProvider.notifier).updatePayable(next.id, next);
      } else {
        await ref.read(payablesProvider.notifier).addPayable(next);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Payable updated' : 'Payable added'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving payable: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final categories = ref.watch(expenseCategoriesProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, widget.isDialog ? 20 : 12, 20, 20),
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
                        _isEditing ? 'Edit Payable' : 'Add Payable',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Track money you owe with due dates and notes',
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
            TextFormField(
              controller: _personController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Person name',
                hintText: 'Who do you owe?',
                errorText: _showValidation && !_isPersonValid
                    ? 'Person name is required'
                    : null,
                prefixIcon: const Icon(Icons.person_rounded),
              ),
              onChanged: (_) {
                _markInteracted();
                setState(() {});
              },
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final isTwoColumn = constraints.maxWidth >= 520;
                final amountField = AmountInput(
                  controller: _amountController,
                  onChanged: (_) {
                    _markInteracted();
                    setState(() {});
                  },
                  showError: _showValidation && !_isAmountValid,
                );
                final dueDateField = ExpenseDatePicker(
                  selectedDate: _dueDate,
                  onChanged: (date) {
                    _markInteracted();
                    setState(() => _dueDate = date);
                  },
                );

                if (isTwoColumn) {
                  return Row(
                    children: [
                      Expanded(child: amountField),
                      const SizedBox(width: 12),
                      Expanded(child: dueDateField),
                    ],
                  );
                }

                return Column(
                  children: [
                    amountField,
                    const SizedBox(height: 12),
                    dueDateField,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            CategorySelector(
              categories: categories,
              selectedCategory: _selectedCategory,
              onSelected: (value) {
                _markInteracted();
                setState(() => _selectedCategory = value);
              },
              showError: _showValidation && _selectedCategory == null,
            ),
            const SizedBox(height: 16),
            ExpenseNotesField(
              controller: _notesController,
              onChanged: (_) => _markInteracted(),
            ),
            const SizedBox(height: 20),
            if (widget.isDialog)
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SaveExpenseButton(
                      label: _isEditing ? 'Save Changes' : 'Save Payable',
                      onPressed: _handleSave,
                      isEnabled: _isFormValid,
                    ),
                  ),
                ],
              )
            else
              SaveExpenseButton(
                label: _isEditing ? 'Save Changes' : 'Save Payable',
                onPressed: _handleSave,
                isEnabled: _isFormValid,
              ),
          ],
        ),
      ),
    );
  }
}
