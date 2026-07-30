import 'package:flutter/material.dart';

import '../../../utils/amount_expression.dart';
import '../../../utils/formatters/formatters.dart';

class AmountInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool showError;

  const AmountInput({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.showError,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Calculator entry ('450+89', '450, 89') shows its running total live.
    final computed = isMultiTermAmount(controller.text)
        ? parseAmountExpression(controller.text)
        : null;

    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(
        labelText: 'Amount',
        hintText: '0.00',
        prefixText: '₹',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        helperText: computed == null
            ? null
            : '= ${AppFormatters.formatCurrency(computed)}',
        errorText: showError ? 'Enter a valid amount' : null,
      ),
      onChanged: onChanged,
    );
  }
}
