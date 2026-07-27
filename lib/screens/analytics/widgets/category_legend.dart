import 'package:flutter/material.dart';

import '../../../core/constants/category_styles.dart';
import '../../../utils/formatters/formatters.dart';
import '../models/analytics_models.dart';

class CategoryLegend extends StatelessWidget {
  final List<CategoryStat> items;
  final int maxItems;

  const CategoryLegend({super.key, required this.items, this.maxItems = 6});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleItems = items.take(maxItems).toList();

    return Column(
      children: visibleItems.map((stat) {
        final style = CategoryStyles.of(stat.category);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: style.tint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, size: 16, color: style.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppFormatters.formatCurrency(stat.amount),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: style.chipTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${stat.percent.toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: style.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
