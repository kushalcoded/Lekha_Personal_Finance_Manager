import 'package:flutter/material.dart';

class ExpenseNotesField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const ExpenseNotesField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      minLines: 3,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: 'Notes',
        hintText: 'Add a note (optional)',
        alignLabelWithHint: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: onChanged,
    );
  }
}
