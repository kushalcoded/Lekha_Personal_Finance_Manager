import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/category_styles.dart';
import '../../providers/ai_providers.dart';
import '../../providers/budget/budget_providers.dart';
import '../../providers/auth/auth_provider.dart';
import '../../widgets/common/ai_text.dart';
import '../../widgets/common/glass.dart';
import '../../utils/formatters/formatters.dart';
import '../../navigation/floating_glass_nav.dart';
import '../history_screen.dart';
import 'providers/analytics_providers.dart';
import 'providers/debt_analytics_providers.dart';
import 'widgets/analytics_charts.dart';
import 'widgets/analytics_empty_state.dart';
import 'widgets/analytics_section.dart';
import 'widgets/analytics_summary_card.dart';
import 'widgets/category_legend.dart';
import 'widgets/chart_card.dart';
import 'widgets/debt_overview_panel.dart';
import 'widgets/net_balance_trend_chart.dart';

/// Analytics screen - view spending analytics
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final userId = ref.watch(currentUserIdProvider) ?? '';

    final expenses = ref.watch(analyticsExpensesProvider(userId));
    final hasData = expenses.isNotEmpty;
    final summary = ref.watch(analyticsSummaryProvider(userId));
    final categoryStats = ref.watch(analyticsCategoryStatsProvider(userId));
    final monthlyTotals = ref.watch(analyticsMonthlyTotalsProvider(userId));
    final trendPoints = ref.watch(analyticsTrendProvider(userId));
    final paymentStats = ref.watch(analyticsPaymentMethodStatsProvider(userId));
    final budgetInsight = ref.watch(analyticsBudgetInsightProvider(userId));
    final budgetMetrics = ref.watch(budgetMetricsProvider(userId));
    final budgetIntelligence = ref.watch(budgetIntelligenceProvider(userId));
    final debtSummary = ref.watch(debtSummaryProvider(userId));
    final overdueDebtStats = ref.watch(debtOverdueStatsProvider(userId));
    final topDebtors = ref.watch(topDebtorsBalanceProvider(userId));
    final topCreditors = ref.watch(topCreditorsBalanceProvider(userId));
    final debtTrend = ref.watch(debtTrendProvider(userId));
    final settlementTotals = ref.watch(monthlySettlementTotalsProvider(userId));
    final period = ref.watch(analyticsPeriodProvider);
    final aiSummary = ref.watch(analyticsAiSummaryProvider(userId));

    final topCategoryStyle = summary.topCategory != null
        ? CategoryStyles.of(summary.topCategory!.category)
        : null;
    final summaryCards = [
      AnalyticsSummaryCard(
        label: 'Total Spend',
        value: AppFormatters.formatCurrency(summary.totalSpent),
        subLabel: _periodLabel(period),
      ),
      AnalyticsSummaryCard(
        label: 'Average Daily',
        value: AppFormatters.formatCurrency(summary.averageDaily),
        subLabel: 'Rolling ${_periodLabel(period)}',
      ),
      AnalyticsSummaryCard(
        label: 'Top Category',
        value: summary.topCategory == null
            ? '-'
            : AppFormatters.formatCurrency(summary.topCategory!.amount),
        subLabel: summary.topCategory?.category ?? 'No data yet',
        accentColor: topCategoryStyle?.color,
      ),
      AnalyticsSummaryCard(
        label: 'Budget Health',
        value: budgetMetrics.hasBudget
            ? '${budgetIntelligence.budgetHealthScore}/100'
            : 'Set budget',
        subLabel: budgetMetrics.hasBudget
            ? 'Projected ${AppFormatters.formatCurrency(budgetIntelligence.projectedMonthEndSpend)}'
            : 'Unlock budget intelligence',
        accentColor: budgetMetrics.isOverBudget
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Cycle history',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + kNavBottomInset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1000;
              final summaryColumns = constraints.maxWidth >= 1100 ? 4 : 2;
              final summaryAspect = constraints.maxWidth >= 720 ? 2.6 : 1.5;

              // Desktop: related sections sit side by side (time view left,
              // distribution right) so charts keep a sane reading width.
              Widget twoUp(Widget a, Widget b) => isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: a),
                          const SizedBox(width: 14),
                          Expanded(child: b),
                        ],
                      ),
                    )
                  : Column(children: [a, const SizedBox(height: 14), b]);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spending Analysis',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  _AiInsightCard(summary: aiSummary),
                  GridView.builder(
                    itemCount: summaryCards.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: summaryColumns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: summaryAspect,
                    ),
                    itemBuilder: (context, index) => summaryCards[index],
                  ),
                  const SizedBox(height: 14),
                  if (!hasData) ...[
                    const AnalyticsEmptyState(
                      title: 'No analytics data yet',
                      message: 'Add a few transactions to unlock insights.',
                    ),
                    const SizedBox(height: 14),
                  ],
                  twoUp(
                    AnalyticsSection(
                      stretch: isWide,
                      title: 'Monthly Spending Overview',
                      subtitle: 'Last 6 months of outflow',
                      child: ChartCard(
                        title: 'Monthly Spending',
                        subtitle: 'Totals by month',
                        child: MonthlySpendingBarChart(data: monthlyTotals),
                      ),
                    ),
                    AnalyticsSection(
                      stretch: isWide,
                      title: 'Category Breakdown',
                      subtitle: 'Share of spend by category',
                      child: ChartCard(
                        title: 'Category Mix',
                        subtitle: 'Top categories in focus',
                        child: categoryStats.isEmpty
                            ? const AnalyticsEmptyState(
                                title: 'No category data',
                                message:
                                    'Add expenses to see category insights.',
                                icon: Icons.pie_chart_rounded,
                              )
                            : isWide
                            ? Row(
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: CategoryPieChart(
                                      categories: categoryStats,
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    flex: 6,
                                    child: CategoryLegend(items: categoryStats),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  CategoryPieChart(categories: categoryStats),
                                  const SizedBox(height: 16),
                                  CategoryLegend(items: categoryStats),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  twoUp(
                    AnalyticsSection(
                      stretch: isWide,
                      title: 'Spending Trends',
                      subtitle: 'Recent movement across the period',
                      trailing: _PeriodSelector(
                        period: period,
                        onChanged: (value) => ref
                            .read(analyticsProvider.notifier)
                            .setPeriod(value),
                      ),
                      child: ChartCard(
                        title: 'Trend Line',
                        subtitle: 'Daily or weekly totals',
                        child: SpendingTrendLineChart(
                          points: trendPoints,
                          period: period,
                        ),
                      ),
                    ),
                    AnalyticsSection(
                      stretch: isWide,
                      title: 'Payment Method Analysis',
                      subtitle: 'Where expenses are paid from',
                      child: ChartCard(
                        title: 'Payment Mix',
                        subtitle: 'Methods captured from notes',
                        child: PaymentMethodBreakdown(stats: paymentStats),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  twoUp(
                    AnalyticsSection(
                      stretch: isWide,
                      title: 'Debt Overview',
                      subtitle: 'Receivables, payables, and net balance',
                      child: ChartCard(
                        title: 'Debt Snapshot',
                        subtitle: 'Outstanding balances and overdue totals',
                        child: DebtOverviewPanel(
                          summary: debtSummary,
                          overdueStats: overdueDebtStats,
                          topDebtors: topDebtors,
                          topCreditors: topCreditors,
                          // Wide = half-pane (~550px), so lists always stack;
                          // single-column tablets get the side-by-side row.
                          stackLists: isWide || constraints.maxWidth < 760,
                        ),
                      ),
                    ),
                    AnalyticsSection(
                      stretch: isWide,
                      title: 'Net Balance Trend',
                      subtitle: 'Monthly receivable vs payable delta',
                      child: ChartCard(
                        title: 'Debt Trend',
                        subtitle: 'Net balance by month',
                        child: NetBalanceTrendChart(points: debtTrend),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  twoUp(
                    AnalyticsSection(
                      stretch: isWide,
                      title: 'Settlement Trends',
                      subtitle: 'Monthly settlement totals',
                      child: ChartCard(
                        title: 'Settlements',
                        subtitle: 'Last 6 months of payments',
                        child: MonthlySpendingBarChart(data: settlementTotals),
                      ),
                    ),
                    AnalyticsSection(
                      stretch: isWide,
                      title: 'Budget Insights',
                      subtitle: 'Baseline vs month-to-date pace',
                      child: ChartCard(
                        title: 'Budget Outlook',
                        subtitle: 'Projected month-end spending',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BudgetInsightsCard(insight: budgetInsight),
                            const SizedBox(height: 16),
                            _BudgetIntelligencePanel(
                              intelligence: budgetIntelligence,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BudgetIntelligencePanel extends StatelessWidget {
  final BudgetIntelligence intelligence;

  const _BudgetIntelligencePanel({required this.intelligence});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 10,
      children: [
        _MiniMetric(
          label: 'Daily burn',
          value: AppFormatters.formatCurrency(intelligence.monthlyBurnRate),
        ),
        _MiniMetric(
          label: 'Weekly average',
          value: AppFormatters.formatCurrency(intelligence.weeklyAverage),
        ),
        _MiniMetric(
          label: 'Savings estimate',
          value: AppFormatters.formatCurrency(intelligence.savingsEstimate),
        ),
        _MiniMetric(
          label: 'Top category',
          value: intelligence.highestSpendingCategory ?? '-',
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;

  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.16)),
      ),
      child: Column(
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _periodLabel(String period) {
  switch (period) {
    case 'week':
      return 'Last 7 days';
    case 'year':
      return 'Last 12 months';
    default:
      return 'Last 30 days';
  }
}

class _AiInsightCard extends StatelessWidget {
  final AsyncValue<String?> summary;

  const _AiInsightCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final content = summary.maybeWhen(
      data: (t) => (t == null || t.trim().isEmpty) ? null : t.trim(),
      orElse: () => null,
    );
    final loading = summary.isLoading;
    if (content == null && !loading) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      // Mockup: AI card carries a 2px violet left edge.
      child: AccentEdgeCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                'AI',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: cs.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: content == null
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Analyzing this period…',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    )
                  : AiText(
                      content,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final String period;
  final ValueChanged<String> onChanged;

  const _PeriodSelector({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const periods = ['week', 'month', 'year'];
    const labels = {'week': '7D', 'month': '30D', 'year': '12M'};

    return Wrap(
      spacing: 6,
      children: periods.map((value) {
        final isSelected = period == value;
        return ChoiceChip(
          label: Text(labels[value] ?? value),
          selected: isSelected,
          onSelected: (_) => onChanged(value),
          labelStyle: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
          ),
          selectedColor: colorScheme.primary.withValues(alpha: 0.18),
          backgroundColor: colorScheme.surface,
          side: BorderSide(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.3),
          ),
        );
      }).toList(),
    );
  }
}
