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

    // Mockup day header: one mono line, day total quiet on the right.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          AppFormatters.formatCurrency(total),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
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
