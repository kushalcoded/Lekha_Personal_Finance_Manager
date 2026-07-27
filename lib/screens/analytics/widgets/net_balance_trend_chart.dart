import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/formatters/formatters.dart';
import '../models/analytics_models.dart';
import 'analytics_empty_state.dart';

class NetBalanceTrendChart extends StatelessWidget {
  final List<TrendPoint> points;

  const NetBalanceTrendChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const AnalyticsEmptyState(
        title: 'No trend data',
        message: 'Your net balance trend will show here.',
        icon: Icons.show_chart_rounded,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxValue = points
        .map((e) => e.total)
        .fold<double>(double.negativeInfinity, (a, b) => a > b ? a : b);
    final minValue = points
        .map((e) => e.total)
        .fold<double>(double.infinity, (a, b) => a < b ? a : b);
    final range = (maxValue - minValue).abs();
    final padding = range <= 0 ? 1.0 : range * 0.2;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: minValue - padding,
          maxY: maxValue + padding,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: range <= 0 ? 1 : range / 4,
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
                  final label = DateFormat('MMM').format(date);
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
                  final label = DateFormat('MMM yyyy').format(date);
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
