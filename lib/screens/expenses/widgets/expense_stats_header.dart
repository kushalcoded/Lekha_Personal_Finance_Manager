import 'package:flutter/material.dart';

import '../../../core/constants/category_styles.dart';
import '../../../utils/formatters/formatters.dart';
import '../../dashboard/widgets/summary_card.dart';
import '../models/expense_view_models.dart';

class ExpenseStatsHeader extends StatelessWidget {
  final ExpenseStats stats;

  const ExpenseStatsHeader({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topCategoryStyle = stats.topCategory == null
        ? null
        : CategoryStyles.of(stats.topCategory!);

    final cards = [
      SummaryCard(
        title: 'Total Expenses',
        value: AppFormatters.formatCurrency(stats.total),
        subtitle: 'All time',
        icon: Icons.account_balance_wallet_rounded,
        accentColor: colorScheme.primary,
      ),
      SummaryCard(
        title: 'Monthly Spend',
        value: AppFormatters.formatCurrency(stats.monthly),
        subtitle: 'Current month',
        icon: Icons.calendar_month_rounded,
        accentColor: colorScheme.tertiary,
      ),
      SummaryCard(
        title: 'Transactions',
        value: stats.transactionCount.toString(),
        subtitle: 'Total entries',
        icon: Icons.receipt_long_rounded,
        accentColor: colorScheme.secondary,
      ),
      SummaryCard(
        title: 'Top Category',
        value: stats.topCategory == null
            ? '-'
            : AppFormatters.formatCurrency(stats.topCategoryTotal),
        subtitle: stats.topCategory ?? 'No data',
        icon: topCategoryStyle?.icon ?? Icons.category_rounded,
        accentColor: topCategoryStyle?.color ?? colorScheme.outline,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        final aspectRatio = constraints.maxWidth >= 1100
            ? 2.8
            : constraints.maxWidth >= 900
            ? 2.6
            : constraints.maxWidth >= 600
            ? 2.4
            : 2.7;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Expense Overview',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              itemCount: cards.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: aspectRatio,
              ),
              itemBuilder: (context, index) => cards[index],
            ),
          ],
        );
      },
    );
  }
}
