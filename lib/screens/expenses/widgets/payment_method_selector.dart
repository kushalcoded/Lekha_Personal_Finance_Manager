import 'package:flutter/material.dart';

class PaymentMethodSelector extends StatelessWidget {
  final List<String> methods;
  final String? selectedMethod;
  final ValueChanged<String> onSelected;
  final bool showError;

  const PaymentMethodSelector({
    super.key,
    required this.methods,
    required this.selectedMethod,
    required this.onSelected,
    required this.showError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Payment Method',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        errorText: showError ? 'Select a payment method' : null,
      ),
      isEmpty: selectedMethod == null,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: methods.map((method) {
          final isSelected = selectedMethod == method;
          return ChoiceChip(
            label: Text(method),
            selected: isSelected,
            onSelected: (_) => onSelected(method),
            labelStyle: theme.textTheme.labelMedium?.copyWith(
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
        }).toList(),
      ),
    );
  }
}
