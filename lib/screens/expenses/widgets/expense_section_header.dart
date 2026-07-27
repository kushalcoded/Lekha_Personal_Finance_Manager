import 'package:flutter/material.dart';

import '../../../utils/formatters/formatters.dart';

class ExpenseSectionHeader extends StatelessWidget {
  final DateTime date;
  final double total;
  final int count;

  const ExpenseSectionHeader({
    super.key,
    required this.date,
    required this.total,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = _labelForDate(date);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count transactions',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text(
          AppFormatters.formatCurrency(total),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  String _labelForDate(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dateOnly = DateTime(value.year, value.month, value.day);

    if (dateOnly == today) {
      return 'Today';
    }
    if (dateOnly == yesterday) {
      return 'Yesterday';
    }
    return AppFormatters.formatDate(value, format: 'EEE, MMM dd');
  }
}
