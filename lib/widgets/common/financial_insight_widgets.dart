import 'package:flutter/material.dart';

import '../../providers/budget/budget_providers.dart';

class InsightCard extends StatelessWidget {
  final SmartFinancialInsight insight;

  const InsightCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _severityColor(colorScheme);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(insight.icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(ColorScheme colorScheme) {
    switch (insight.severity) {
      case InsightSeverity.danger:
        return colorScheme.error;
      case InsightSeverity.warning:
        return colorScheme.secondary;
      case InsightSeverity.healthy:
        return colorScheme.tertiary;
      case InsightSeverity.info:
        return colorScheme.primary;
    }
  }
}

class InsightBanner extends StatelessWidget {
  final SmartFinancialInsight insight;

  const InsightBanner({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    return InsightCard(insight: insight);
  }
}
