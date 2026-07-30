import 'package:flutter/material.dart';

import '../../../models/debt/person_balance.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/metric_tile.dart';
import '../models/debt_models.dart';

class DebtOverviewPanel extends StatelessWidget {
  final DebtSummary summary;
  final DebtOverdueStats overdueStats;
  final List<PersonBalance> topDebtors;
  final List<PersonBalance> topCreditors;

  /// Stack the debtor/creditor lists vertically (narrow panes). Decided by
  /// the caller — a LayoutBuilder here breaks the desktop IntrinsicHeight
  /// rows (zero intrinsic height in release builds).
  final bool stackLists;

  const DebtOverviewPanel({
    super.key,
    required this.summary,
    required this.overdueStats,
    required this.topDebtors,
    required this.topCreditors,
    this.stackLists = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final listSection = stackLists
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BalanceList(
                title: 'Top debtors',
                entries: topDebtors,
                amountSelector: (entry) => entry.receivableTotal,
              ),
              const SizedBox(height: 12),
              _BalanceList(
                title: 'Top creditors',
                entries: topCreditors,
                amountSelector: (entry) => entry.payableTotal,
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _BalanceList(
                  title: 'Top debtors',
                  entries: topDebtors,
                  amountSelector: (entry) => entry.receivableTotal,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _BalanceList(
                  title: 'Top creditors',
                  entries: topCreditors,
                  amountSelector: (entry) => entry.payableTotal,
                ),
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            MetricTile(
              label: 'Receivables',
              value: AppFormatters.formatCurrency(summary.totalReceivables),
            ),
            MetricTile(
              label: 'Payables',
              value: AppFormatters.formatCurrency(summary.totalPayables),
              valueColor: colorScheme.error,
            ),
            MetricTile(
              label: 'Net balance',
              value: AppFormatters.formatCurrency(summary.netBalance),
              valueColor: summary.netBalance >= 0
                  ? colorScheme.tertiary
                  : colorScheme.error,
            ),
            MetricTile(
              label: 'Settled',
              value: AppFormatters.formatCurrency(summary.settledAmount),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            MetricTile(
              label: 'Overdue receivables',
              value: overdueStats.overdueReceivablesCount == 0
                  ? 'None'
                  : AppFormatters.formatCurrency(
                      overdueStats.overdueReceivablesTotal,
                    ),
              valueColor: overdueStats.overdueReceivablesCount > 0
                  ? colorScheme.error
                  : null,
            ),
            MetricTile(
              label: 'Overdue payables',
              value: overdueStats.overduePayablesCount == 0
                  ? 'None'
                  : AppFormatters.formatCurrency(
                      overdueStats.overduePayablesTotal,
                    ),
              valueColor: overdueStats.overduePayablesCount > 0
                  ? colorScheme.error
                  : null,
            ),
            MetricTile(
              label: 'Active debtors',
              value: summary.activeDebtors.toString(),
            ),
            MetricTile(
              label: 'Active creditors',
              value: summary.activeCreditors.toString(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (topDebtors.isNotEmpty || topCreditors.isNotEmpty) listSection,
      ],
    );
  }
}

class _BalanceList extends StatelessWidget {
  final String title;
  final List<PersonBalance> entries;
  final double Function(PersonBalance) amountSelector;

  const _BalanceList({
    required this.title,
    required this.entries,
    required this.amountSelector,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          'No data yet',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...entries.take(3).map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.person,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  AppFormatters.formatCurrency(amountSelector(entry)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
