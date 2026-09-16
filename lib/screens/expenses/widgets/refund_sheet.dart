import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/expense/expense_model.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../utils/amount_expression.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/top_notice.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import 'amount_input.dart';
import 'expense_notes_field.dart';
import 'save_expense_button.dart';

/// Money coming back on something you already recorded — a returned order, a
/// cancelled ticket, a duplicate charge reversed.
///
/// It is stored as an ordinary expense with a **negative** amount in the same
/// category, which is why nothing else in the app had to change: every total,
/// chart, export and sync already folds amounts, so the money simply nets off
/// where it was spent. Spending could only ever go up before this.
Future<void> showRefundSheet(BuildContext context, Expense original) {
  return showResponsiveSheet<void>(
    context,
    maxWidth: 460,
    mobileChild: _RefundForm(original: original),
    desktopChild: _RefundForm(original: original),
  );
}

class _RefundForm extends ConsumerStatefulWidget {
  final Expense original;

  const _RefundForm({required this.original});

  @override
  ConsumerState<_RefundForm> createState() => _RefundFormState();
}

class _RefundFormState extends ConsumerState<_RefundForm> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.original.amount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Capped at what was spent. A refund larger than the purchase is a
  /// different thing — income — and pretending otherwise would let a category
  /// drift negative for no visible reason.
  double? get _value {
    final value = parseAmountExpression(_amountController.text.trim());
    if (value == null || value <= 0) return null;
    return value > widget.original.amount ? null : value;
  }

  Future<void> _save() async {
    final value = _value;
    if (value == null) {
      setState(() => _showValidation = true);
      return;
    }
    final note = _notesController.text.trim();
    final now = DateTime.now();
    final label = widget.original.description?.trim().isNotEmpty == true
        ? widget.original.description!.trim()
        : widget.original.category;

    await ref
        .read(expensesProvider.notifier)
        .addExpense(
          Expense(
            id: const Uuid().v4(),
            userId: widget.original.userId,
            // Negative on purpose — see the note on showRefundSheet.
            amount: -value,
            category: widget.original.category,
            description: note.isEmpty ? 'Refund · $label' : note,
            date: now,
            paymentMethod: widget.original.paymentMethod,
            createdAt: now,
          ),
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    showNotice('Refund recorded · ${AppFormatters.formatCurrency(value)}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = _value;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record a refund',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.original.category} · '
            '${AppFormatters.formatCurrency(widget.original.amount)} spent',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          AmountInput(
            controller: _amountController,
            onChanged: (_) => setState(() {}),
            showError: _showValidation && value == null,
          ),
          if (_showValidation && value == null) ...[
            const SizedBox(height: 6),
            Text(
              'Enter an amount up to '
              '${AppFormatters.formatCurrency(widget.original.amount)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ExpenseNotesField(controller: _notesController, onChanged: (_) {}),
          const SizedBox(height: 8),
          Text(
            'Comes off ${widget.original.category} for this cycle. The '
            'original expense stays as it was.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          SaveExpenseButton(
            label: value == null
                ? 'Record refund'
                : 'Record ${AppFormatters.formatCurrency(value)} back',
            isEnabled: value != null,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
