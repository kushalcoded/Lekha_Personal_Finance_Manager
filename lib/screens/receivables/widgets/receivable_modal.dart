import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/receivable/receivable_model.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../expenses/widgets/amount_input.dart';
import '../../expenses/widgets/expense_date_picker.dart';
import '../../expenses/widgets/expense_notes_field.dart';
import '../../expenses/widgets/save_expense_button.dart';

Future<void> showAddReceivableModal(BuildContext context) {
  return _showReceivableModal(
    context,
    child: const ReceivableForm(isDialog: false),
    dialogChild: const ReceivableForm(isDialog: true),
  );
}

Future<void> showEditReceivableModal(
  BuildContext context, {
  required Receivable receivable,
}) {
  return _showReceivableModal(
    context,
    child: ReceivableForm(receivable: receivable, isDialog: false),
    dialogChild: ReceivableForm(receivable: receivable, isDialog: true),
  );
}

Future<void> _showReceivableModal(
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

class ReceivableForm extends ConsumerStatefulWidget {
  final Receivable? receivable;
  final bool isDialog;

  const ReceivableForm({super.key, this.receivable, required this.isDialog});

  @override
  ConsumerState<ReceivableForm> createState() => _ReceivableFormState();
}

class _ReceivableFormState extends ConsumerState<ReceivableForm> {
  late final TextEditingController _personController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  late DateTime _dueDate;
  bool _showValidation = false;

  bool get _isEditing => widget.receivable != null;

  @override
  void initState() {
    super.initState();
    final receivable = widget.receivable;
    _personController = TextEditingController(
      text: receivable?.fromPerson ?? '',
    );
    _amountController = TextEditingController(
      text: receivable == null ? '' : receivable.amount.toStringAsFixed(2),
    );
    _notesController = TextEditingController(
      text: receivable?.description ?? '',
    );
    _dueDate = receivable?.dueDate ?? DateTime.now();
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

  bool get _isFormValid => _isPersonValid && _isAmountValid;

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
    final receivable = widget.receivable;
    final userId = ref.read(currentUserIdProvider) ?? localUserId;
    final next = Receivable(
      id: receivable?.id ?? const Uuid().v4(),
      userId: receivable?.userId ?? userId,
      fromPerson: _personController.text.trim(),
      amount: double.parse(_amountController.text.trim()),
      description: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      dueDate: _dueDate,
      isPaid: receivable?.isPaid ?? false,
      createdAt: receivable?.createdAt ?? now,
      updatedAt: _isEditing ? now : null,
    );

    try {
      if (_isEditing) {
        await ref
            .read(receivablesProvider.notifier)
            .updateReceivable(next.id, next);
      } else {
        await ref.read(receivablesProvider.notifier).addReceivable(next);
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Receivable updated' : 'Receivable added'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving receivable: $e')));
    }
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
                        _isEditing ? 'Edit Receivable' : 'Add Receivable',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Track money owed, due dates, and notes',
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
                hintText: 'Who owes you?',
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
                      label: _isEditing ? 'Save Changes' : 'Save Receivable',
                      onPressed: _handleSave,
                      isEnabled: _isFormValid,
                    ),
                  ),
                ],
              )
            else
              SaveExpenseButton(
                label: _isEditing ? 'Save Changes' : 'Save Receivable',
                onPressed: _handleSave,
                isEnabled: _isFormValid,
              ),
          ],
        ),
      ),
    );
  }
}
