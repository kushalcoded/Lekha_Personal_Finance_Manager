import 'package:flutter/material.dart';

import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/metric_tile.dart';
import '../models/analytics_models.dart';

class RecurringObligationsPanel extends StatelessWidget {
  final RecurringObligationSummary summary;
  final BurnRateForecast forecast;
  final List<CategoryStat> topCategories;

  const RecurringObligationsPanel({
    super.key,
    required this.summary,
    required this.forecast,
    required this.topCategories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            MetricTile(
              label: 'Monthly fixed',
              value: AppFormatters.formatCurrency(summary.monthlyTotal),
            ),
            MetricTile(
              label: 'Annualized',
              value: AppFormatters.formatCurrency(summary.annualTotal),
            ),
            MetricTile(
              label: 'Upcoming (7d)',
              value: summary.upcomingCount == 0
                  ? 'None'
                  : AppFormatters.formatCurrency(summary.upcomingTotal),
            ),
            MetricTile(
              label: 'Daily fixed',
              value: AppFormatters.formatCurrency(summary.averageDaily),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Burn-rate forecast',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            MetricTile(
              label: 'Daily spend',
              value: AppFormatters.formatCurrency(forecast.actualDaily),
            ),
            MetricTile(
              label: 'Daily fixed',
              value: AppFormatters.formatCurrency(forecast.recurringDaily),
            ),
            MetricTile(
              label: 'Projected month end',
              value: AppFormatters.formatCurrency(forecast.projectedMonthEnd),
            ),
            MetricTile(
              label: 'Budget remaining',
              value: forecast.budget > 0
                  ? AppFormatters.formatCurrency(forecast.remainingBudget)
                  : 'Set budget',
              valueColor:
                  forecast.budget > 0 && forecast.remainingBudget < 0
                      ? colorScheme.error
                      : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (topCategories.isNotEmpty) ...[
          Text(
            'Top fixed categories',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            children: topCategories
                .take(3)
                .map(
                  (stat) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CategoryRow(stat: stat),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final CategoryStat stat;

  const _CategoryRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            stat.category,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          AppFormatters.formatCurrency(stat.amount),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
