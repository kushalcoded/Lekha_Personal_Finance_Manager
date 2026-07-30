import '../../../utils/amount_expression.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/payable/payable_model.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../utils/formatters/formatters.dart';
import '../../expenses/widgets/amount_input.dart';
import '../../expenses/widgets/expense_notes_field.dart';
import '../../expenses/widgets/save_expense_button.dart';

Future<void> showPayableSettlementModal(
  BuildContext context, {
  required Payable payable,
}) {
  return showResponsiveSheet(
    context,
    maxWidth: 520,
    mobileChild: PayableSettlementForm(payable: payable, isDialog: false),
    desktopChild: PayableSettlementForm(payable: payable, isDialog: true),
  );
}

class PayableSettlementForm extends ConsumerStatefulWidget {
  final Payable payable;
  final bool isDialog;

  const PayableSettlementForm({
    super.key,
    required this.payable,
    required this.isDialog,
  });

  @override
  ConsumerState<PayableSettlementForm> createState() =>
      _PayableSettlementFormState();
}

class _PayableSettlementFormState extends ConsumerState<PayableSettlementForm> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.payable.remainingAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isAmountValid {
    final value = parseAmountExpression(_amountController.text.trim());
    return value != null &&
        value > 0 &&
        value <= widget.payable.remainingAmount;
  }

  void _markInteracted() {
    if (!_showValidation) {
      setState(() => _showValidation = true);
    }
  }

  Future<void> _handleSave() async {
    if (!_isAmountValid) {
      setState(() => _showValidation = true);
      return;
    }

    final amount = (parseAmountExpression(_amountController.text.trim()) ?? 0);
    final note = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    await ref
        .read(payablesProvider.notifier)
        .addSettlement(widget.payable.id, amount, note: note);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settlement recorded')));
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
                        'Settle Payable',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Remaining ${AppFormatters.formatCurrency(widget.payable.remainingAmount)}',
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
            AmountInput(
              controller: _amountController,
              onChanged: (_) {
                _markInteracted();
                setState(() {});
              },
              showError: _showValidation && !_isAmountValid,
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
                      label: 'Record Settlement',
                      onPressed: _handleSave,
                      isEnabled: _isAmountValid,
                    ),
                  ),
                ],
              )
            else
              SaveExpenseButton(
                label: 'Record Settlement',
                onPressed: _handleSave,
                isEnabled: _isAmountValid,
              ),
          ],
        ),
      ),
    );
  }
}
