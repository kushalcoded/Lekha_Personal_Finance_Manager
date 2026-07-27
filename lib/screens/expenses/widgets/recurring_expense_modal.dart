import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/recurring/recurring_expense_template.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/storage/storage_providers.dart';
import 'amount_input.dart';
import 'category_selector.dart';
import 'expense_date_picker.dart';
import 'expense_notes_field.dart';
import 'payment_method_selector.dart';
import 'save_expense_button.dart';

Future<void> showRecurringExpenseModal(
  BuildContext context, {
  RecurringExpenseTemplate? template,
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
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: RecurringExpenseForm(template: template, isDialog: true),
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: RecurringExpenseForm(template: template),
        ),
      );
    },
  );
}

class RecurringExpenseForm extends ConsumerStatefulWidget {
  final RecurringExpenseTemplate? template;
  final bool isDialog;

  const RecurringExpenseForm({super.key, this.template, this.isDialog = false});

  @override
  ConsumerState<RecurringExpenseForm> createState() =>
      _RecurringExpenseFormState();
}

class _RecurringExpenseFormState extends ConsumerState<RecurringExpenseForm> {
  static const _categories = <String>[
    'Food',
    'Friends',
    'Fuel',
    'Shopping',
    'Luxury',
    'Rent',
    'Bills',
    'Subscriptions',
    'Travel',
    'Health',
    'Gifts',
    'Entertainment',
    'Investment',
    'Miscellaneous',
  ];

  static const _paymentMethods = <String>[
    'Cash',
    'GPay',
    'PhonePe',
    'Paytm',
    'Bank Transfer',
    'Card',
  ];

  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedCategory;
  String? _selectedPaymentMethod;
  DateTime _nextDueDate = DateTime.now();
  RecurringFrequency _frequency = RecurringFrequency.monthly;
  bool _showValidation = false;

  bool get _editing => widget.template != null;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    if (template != null) {
      _amountController.text = template.amount.toStringAsFixed(2);
      _notesController.text = template.notes ?? '';
      _selectedCategory = template.category;
      _selectedPaymentMethod = template.paymentMethod;
      _nextDueDate = template.nextDueDate;
      _frequency = template.frequency;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isAmountValid {
    final value = double.tryParse(_amountController.text.trim());
    return value != null && value > 0;
  }

  bool get _isFormValid {
    return _isAmountValid &&
        _selectedCategory != null &&
        _selectedPaymentMethod != null;
  }

  void _markInteracted() {
    if (!_showValidation) {
      setState(() => _showValidation = true);
    }
  }

  Future<void> _save() async {
    if (!_isFormValid) {
      setState(() => _showValidation = true);
      return;
    }

    final userId = ref.read(currentUserIdProvider);
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to save recurring templates.'),
        ),
      );
      return;
    }

    final now = DateTime.now();
    final existing = widget.template;
    final template = RecurringExpenseTemplate(
      id: existing?.id ?? const Uuid().v4(),
      userId: existing?.userId ?? userId,
      amount: double.parse(_amountController.text.trim()),
      category: _selectedCategory!,
      paymentMethod: _selectedPaymentMethod!,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      frequency: _frequency,
      nextDueDate: _nextDueDate,
      isActive: existing?.isActive ?? true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: existing == null ? null : now,
    );

    if (existing == null) {
      await ref.read(recurringTemplatesProvider.notifier).addTemplate(template);
    } else {
      await ref
          .read(recurringTemplatesProvider.notifier)
          .updateTemplate(template.id, template);
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                        _editing
                            ? 'Edit Recurring Expense'
                            : 'Create Recurring Expense',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Build a template for automatic expense generation',
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
                final split = constraints.maxWidth >= 520;
                final amountField = AmountInput(
                  controller: _amountController,
                  onChanged: (_) {
                    _markInteracted();
                    setState(() {});
                  },
                  showError: _showValidation && !_isAmountValid,
                );
                final dateField = ExpenseDatePicker(
                  selectedDate: _nextDueDate,
                  onChanged: (value) {
                    _markInteracted();
                    setState(() => _nextDueDate = value);
                  },
                );
                if (!split) {
                  return Column(
                    children: [
                      amountField,
                      const SizedBox(height: 12),
                      dateField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: amountField),
                    const SizedBox(width: 12),
                    Expanded(child: dateField),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            CategorySelector(
              categories: _categories,
              selectedCategory: _selectedCategory,
              onSelected: (value) {
                _markInteracted();
                setState(() => _selectedCategory = value);
              },
              showError: _showValidation && _selectedCategory == null,
            ),
            const SizedBox(height: 16),
            PaymentMethodSelector(
              methods: _paymentMethods,
              selectedMethod: _selectedPaymentMethod,
              onSelected: (value) {
                _markInteracted();
                setState(() => _selectedPaymentMethod = value);
              },
              showError: _showValidation && _selectedPaymentMethod == null,
            ),
            const SizedBox(height: 16),
            Text(
              'Frequency',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: RecurringFrequency.values.map((value) {
                final selected = value == _frequency;
                return ChoiceChip(
                  label: Text(value.label),
                  selected: selected,
                  onSelected: (_) {
                    _markInteracted();
                    setState(() => _frequency = value);
                  },
                );
              }).toList(),
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
                      label: _editing ? 'Save Changes' : 'Save Template',
                      onPressed: _save,
                      isEnabled: _isFormValid,
                    ),
                  ),
                ],
              )
            else
              SaveExpenseButton(
                label: _editing ? 'Save Changes' : 'Save Template',
                onPressed: _save,
                isEnabled: _isFormValid,
              ),
          ],
        ),
      ),
    );
  }

}
