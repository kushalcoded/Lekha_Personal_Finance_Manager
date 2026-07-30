import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/category_styles.dart';
import '../../../utils/formatters/formatters.dart';
import '../models/analytics_models.dart';
import 'analytics_empty_state.dart';

class CategoryPieChart extends StatefulWidget {
  final List<CategoryStat> categories;

  const CategoryPieChart({super.key, required this.categories});

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) {
      return const AnalyticsEmptyState(
        title: 'No category data',
        message: 'Track expenses to see category insights.',
        icon: Icons.pie_chart_rounded,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AspectRatio(
      aspectRatio: 1.25,
      child: PieChart(
        PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (event, response) {
              if (!event.isInterestedForInteractions ||
                  response == null ||
                  response.touchedSection == null) {
                setState(() => _touchedIndex = null);
                return;
              }
              setState(
                () => _touchedIndex =
                    response.touchedSection!.touchedSectionIndex,
              );
            },
          ),
          sectionsSpace: 2,
          centerSpaceRadius: 40,
          centerSpaceColor: colorScheme.surface,
          sections: widget.categories.asMap().entries.map((entry) {
            final index = entry.key;
            final stat = entry.value;
            final style = CategoryStyles.of(stat.category);
            final isTouched = _touchedIndex == index;
            final radius = isTouched ? 58.0 : 52.0;
            final percentLabel = stat.percent >= 8
                ? '${stat.percent.toStringAsFixed(0)}%'
                : '';

            return PieChartSectionData(
              color: style.color,
              value: stat.amount,
              radius: radius,
              title: percentLabel,
              titleStyle: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
              titlePositionPercentageOffset: 0.65,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class MonthlySpendingBarChart extends StatelessWidget {
  final List<MonthlyTotal> data;

  const MonthlySpendingBarChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const AnalyticsEmptyState(
        title: 'No monthly data',
        message: 'Your monthly totals will appear here.',
        icon: Icons.bar_chart_rounded,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxValue = data
        .map((e) => e.total)
        .fold<double>(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          maxY: maxValue <= 0 ? 1 : maxValue * 1.2,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipPadding: const EdgeInsets.all(8),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final month = data[group.x.toInt()].month;
                final label = DateFormat('MMM').format(month);
                return BarTooltipItem(
                  '$label\n${AppFormatters.formatCurrency(rod.toY)}',
                  theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ) ??
                      const TextStyle(),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) {
                    return const SizedBox.shrink();
                  }
                  final label = DateFormat('MMM').format(data[index].month);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxValue <= 0 ? 1 : maxValue / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colorScheme.outline.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: data.asMap().entries.map((entry) {
            final index = entry.key;
            final total = entry.value.total;
            // Spec chart rule: history bars 32% accent, current bar full.
            final isCurrent = index == data.length - 1;
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: total,
                  width: 14,
                  borderRadius: BorderRadius.circular(6),
                  color: isCurrent
                      ? colorScheme.primary
                      : colorScheme.primary.withValues(alpha: 0.32),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxValue <= 0 ? 1 : maxValue * 1.05,
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class SpendingTrendLineChart extends StatelessWidget {
  final List<TrendPoint> points;
  final String period;

  const SpendingTrendLineChart({
    super.key,
    required this.points,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const AnalyticsEmptyState(
        title: 'No trend data',
        message: 'Your spending trend will show here.',
        icon: Icons.show_chart_rounded,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxValue = points
        .map((e) => e.total)
        .fold<double>(0.0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxValue <= 0 ? 1 : maxValue * 1.2,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxValue <= 0 ? 1 : maxValue / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colorScheme.outline.withValues(alpha: 0.15),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  final date = points[index].date;
                  String label;
                  if (period == 'week') {
                    label = DateFormat('E').format(date);
                  } else if (period == 'month') {
                    label = DateFormat('MMM d').format(date);
                  } else {
                    label = DateFormat('MMM').format(date);
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipPadding: const EdgeInsets.all(8),
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final index = spot.x.toInt();
                  final date = points[index].date;
                  final label = period == 'week'
                      ? DateFormat('EEE, MMM d').format(date)
                      : DateFormat('MMM d').format(date);
                  return LineTooltipItem(
                    '$label\n${AppFormatters.formatCurrency(spot.y)}',
                    theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ) ??
                        const TextStyle(),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points
                  .asMap()
                  .entries
                  .map(
                    (entry) => FlSpot(entry.key.toDouble(), entry.value.total),
                  )
                  .toList(),
              isCurved: true,
              curveSmoothness: 0.25,
              color: colorScheme.primary,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: colorScheme.surface,
                    strokeColor: colorScheme.primary,
                    strokeWidth: 2,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PaymentMethodBreakdown extends StatelessWidget {
  final List<PaymentMethodStat> stats;

  const PaymentMethodBreakdown({super.key, required this.stats});

  Color _methodColor(BuildContext context, String method) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (method) {
      case 'GPay':
        return const Color(0xFF3AA76D);
      case 'PhonePe':
        return const Color(0xFF6E7BB8);
      case 'Paytm':
        return const Color(0xFF4A8CC5);
      case 'Cash':
        return const Color(0xFFB28A4A);
      case 'Card':
        return colorScheme.secondary;
      case 'Bank Transfer':
        return colorScheme.tertiary;
      default:
        return colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final total = stats.fold<double>(0.0, (sum, stat) => sum + stat.amount);

    if (total <= 0) {
      return const AnalyticsEmptyState(
        title: 'Payment methods not tracked yet',
        message: 'Add payment method info to unlock this breakdown.',
        icon: Icons.credit_card_rounded,
      );
    }

    return Column(
      children: stats.map((stat) {
        final color = _methodColor(context, stat.method);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stat.method,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    AppFormatters.formatCurrency(stat.amount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(stat.share * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: stat.share,
                  minHeight: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class BudgetInsightsCard extends StatelessWidget {
  final BudgetInsight insight;

  const BudgetInsightsCard({super.key, required this.insight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (insight.baseline <= 0 && insight.current <= 0 && insight.budget <= 0) {
      return const AnalyticsEmptyState(
        title: 'No budget insights yet',
        message: 'Set a budget or add expenses to unlock insights.',
        icon: Icons.flag_rounded,
      );
    }

    final progressColor = insight.progress <= 1
        ? colorScheme.primary
        : colorScheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Month-to-date progress',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: insight.progress > 1 ? 1 : insight.progress,
            minHeight: 10,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _InsightMetric(
              label: insight.budget > 0 ? 'Monthly budget' : 'Baseline',
              value: AppFormatters.formatCurrency(
                insight.budget > 0 ? insight.budget : insight.baseline,
              ),
            ),
            _InsightMetric(
              label: 'Current month',
              value: AppFormatters.formatCurrency(insight.current),
            ),
            _InsightMetric(
              label: 'Projected',
              value: AppFormatters.formatCurrency(insight.projected),
            ),
            if (insight.budget > 0)
              _InsightMetric(
                label: insight.remaining < 0 ? 'Overspent' : 'Remaining',
                value: AppFormatters.formatCurrency(insight.remaining.abs()),
              ),
            if (insight.budget > 0)
              _InsightMetric(
                label: 'Health score',
                value: '${insight.healthScore}/100',
              ),
          ],
        ),
      ],
    );
  }
}

class _InsightMetric extends StatelessWidget {
  final String label;
  final String value;

  const _InsightMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
