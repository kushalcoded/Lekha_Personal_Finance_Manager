import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/category/expense_category.dart';
import '../../../models/expense/expense_model.dart';
import '../../../providers/auth/auth_provider.dart';
import '../../../providers/categories/category_providers.dart';
import '../../../providers/storage/storage_providers.dart';
import '../../../utils/amount_expression.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/top_notice.dart';
import '../../../widgets/responsive/responsive_sheet.dart';
import '../../expenses/widgets/amount_input.dart';
import '../../expenses/widgets/expense_notes_field.dart';
import '../../expenses/widgets/save_expense_button.dart';

/// The category a bill payment is filed under. Transfer-kind, so it moves the
/// card balance and counts in no spending total — the purchases it settles
/// were counted when they were made.
const kCardBillCategory = 'Card bill';

/// Pay some or all of a card bill.
Future<void> showPayBillSheet(
  BuildContext context, {
  required String method,
  required double outstanding,
  required double statementDue,
}) {
  return showResponsiveSheet<void>(
    context,
    maxWidth: 460,
    mobileChild: _PayBillForm(
      method: method,
      outstanding: outstanding,
      statementDue: statementDue,
    ),
    desktopChild: _PayBillForm(
      method: method,
      outstanding: outstanding,
      statementDue: statementDue,
    ),
  );
}

class _PayBillForm extends ConsumerStatefulWidget {
  final String method;
  final double outstanding;
  final double statementDue;

  const _PayBillForm({
    required this.method,
    required this.outstanding,
    required this.statementDue,
  });

  @override
  ConsumerState<_PayBillForm> createState() => _PayBillFormState();
}

class _PayBillFormState extends ConsumerState<_PayBillForm> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    // The statement is what is actually being asked for; the full balance
    // includes purchases made since it closed, which are next month's.
    final prefill = widget.statementDue > 0
        ? widget.statementDue
        : widget.outstanding;
    _amountController.text = prefill
        .clamp(0, double.infinity)
        .toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double? get _value {
    final value = parseAmountExpression(_amountController.text.trim());
    return value != null && value > 0 ? value : null;
  }

  Future<void> _save() async {
    final value = _value;
    if (value == null) {
      setState(() => _showValidation = true);
      return;
    }

    // The category has to exist before the payment can be filed under it, and
    // it is offered rather than seeded: someone with no credit card should
    // never find "Card bill" in their picker.
    final categories = ref.read(categoriesProvider);
    if (!categories.any(
      (c) => c.name.toLowerCase() == kCardBillCategory.toLowerCase(),
    )) {
      await ref
          .read(categoriesProvider.notifier)
          .addCategory(
            name: kCardBillCategory,
            iconKey: 'credit_card',
            colorHex: '#8FA3BF',
            kind: CategoryKind.transfer,
          );
    }

    final now = DateTime.now();
    final note = _notesController.text.trim();
    await ref
        .read(expensesProvider.notifier)
        .addExpense(
          Expense(
            id: const Uuid().v4(),
            userId: ref.read(currentUserIdProvider) ?? '',
            amount: value,
            category: kCardBillCategory,
            description: note.isEmpty ? '${widget.method} bill' : note,
            // Filed against the card, which is what makes it subtract from
            // that card's balance. Slightly odd as "paid via", but transfers
            // are excluded from every total, so it never surfaces elsewhere.
            paymentMethod: widget.method,
            date: now,
            createdAt: now,
          ),
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    showNotice(
      '${AppFormatters.formatCurrency(value)} paid to ${widget.method}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = _value;
    final left = value == null ? null : widget.outstanding - value;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pay ${widget.method}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${AppFormatters.formatCurrency(widget.outstanding)} outstanding',
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
          const SizedBox(height: 8),
          Text(
            left == null
                ? 'Paying less than the full bill is fine — the rest carries '
                      'to next month.'
                : left > 0.005
                ? '${AppFormatters.formatCurrency(left)} would carry to next '
                      'month.'
                : left < -0.005
                ? 'More than the balance — the card would be '
                      '${AppFormatters.formatCurrency(left.abs())} in credit.'
                : 'This clears the card.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          ExpenseNotesField(controller: _notesController, onChanged: (_) {}),
          const SizedBox(height: 8),
          Text(
            'Recorded as a transfer, so it moves the card balance and counts '
            'in no spending total — the purchases already did.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          SaveExpenseButton(
            label: value == null
                ? 'Record payment'
                : 'Pay ${AppFormatters.formatCurrency(value)}',
            isEnabled: value != null,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
