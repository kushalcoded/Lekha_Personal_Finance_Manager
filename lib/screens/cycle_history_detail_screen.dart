import 'package:flutter/material.dart';

import '../core/constants/category_styles.dart';
import '../models/history/cycle_history_snapshot.dart';
import '../utils/formatters/formatters.dart';

class CycleHistoryDetailScreen extends StatelessWidget {
  final CycleHistorySnapshot snapshot;

  const CycleHistoryDetailScreen({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedCategories = snapshot.categoryBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedExpenses = [...snapshot.expenses]
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(title: const Text('Cycle Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppFormatters.formatDate(snapshot.cycleStartDate)} - ${AppFormatters.formatDate(snapshot.cycleEndDate)}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Archived ${AppFormatters.getRelativeTime(snapshot.archivedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _DetailMetricCard(
                  label: 'Total Expenses',
                  value: AppFormatters.formatCurrency(snapshot.totalExpenses),
                ),
                _DetailMetricCard(
                  label: 'Budget',
                  value: AppFormatters.formatCurrency(snapshot.cycleBudget),
                ),
                _DetailMetricCard(
                  label: 'Salary',
                  value: AppFormatters.formatCurrency(snapshot.cycleSalary),
                ),
                _DetailMetricCard(
                  label: 'Budget - Expenses',
                  value: AppFormatters.formatCurrency(
                    snapshot.budgetMinusExpenses,
                  ),
                ),
                _DetailMetricCard(
                  label: 'Salary - Budget',
                  value: AppFormatters.formatCurrency(
                    snapshot.salaryMinusBudget,
                  ),
                ),
                _DetailMetricCard(
                  label: 'Transactions',
                  value: snapshot.transactionCount.toString(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Category Breakdown',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (sortedCategories.isEmpty)
              const _SectionEmptyState(
                message: 'No category data was captured for this cycle.',
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _cardDecoration(context),
                child: Column(
                  children: sortedCategories.map((entry) {
                    final style = CategoryStyles.of(entry.key);
                    final share = snapshot.totalExpenses <= 0
                        ? 0.0
                        : entry.value / snapshot.totalExpenses;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: style.color.withValues(
                              alpha: 0.14,
                            ),
                            child: Icon(
                              style.icon,
                              size: 16,
                              color: style.color,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.key,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: share.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  borderRadius: BorderRadius.circular(20),
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    style.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                AppFormatters.formatCurrency(entry.value),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                AppFormatters.formatPercentage(share),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Cycle Expenses',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            if (sortedExpenses.isEmpty)
              const _SectionEmptyState(
                message: 'No expenses were captured for this cycle.',
              )
            else
              Container(
                decoration: _cardDecoration(context),
                child: Column(
                  children: sortedExpenses.map((expense) {
                    final style = CategoryStyles.of(expense.category);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: style.color.withValues(alpha: 0.14),
                        child: Icon(style.icon, size: 18, color: style.color),
                      ),
                      title: Text(expense.description ?? expense.category),
                      subtitle: Text(
                        '${expense.category} • ${AppFormatters.formatDate(expense.date)}',
                      ),
                      trailing: Text(
                        AppFormatters.formatCurrency(expense.amount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailMetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _DetailMetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SectionEmptyState extends StatelessWidget {
  final String message;

  const _SectionEmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(context),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration(BuildContext context) {
  final primary = Theme.of(context).colorScheme.primary;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(18),
    gradient: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        primary.withValues(alpha: 0.16),
        const Color(0xFF131318).withValues(alpha: 0.42),
        const Color(0xFF131318).withValues(alpha: 0.42),
      ],
      stops: const [0.0, 0.4, 1.0],
    ),
    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
  );
}
