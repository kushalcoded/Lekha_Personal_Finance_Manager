import 'package:flutter/material.dart';

import '../../../core/constants/category_styles.dart';

class CategorySelector extends StatelessWidget {
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String> onSelected;
  final bool showError;

  const CategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
    required this.showError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Category',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        errorText: showError ? 'Select a category' : null,
      ),
      isEmpty: selectedCategory == null,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: categories.map((category) {
          final style = CategoryStyles.of(category);
          final isSelected = selectedCategory == category;
          return ChoiceChip(
            label: Text(category),
            avatar: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: style.tint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(style.icon, size: 12, color: style.color),
            ),
            selected: isSelected,
            onSelected: (_) => onSelected(category),
            labelStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isSelected ? style.color : colorScheme.onSurface,
            ),
            selectedColor: style.chipTint,
            backgroundColor: colorScheme.surface,
            side: BorderSide(
              color: isSelected
                  ? style.color.withValues(alpha: 0.6)
                  : colorScheme.outline.withValues(alpha: 0.3),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }).toList(),
      ),
    );
  }
}
