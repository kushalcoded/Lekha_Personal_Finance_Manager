import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/category_styles.dart';
import '../providers/auth/auth_provider.dart';
import '../utils/formatters/formatters.dart';
import 'cycle_history_detail_screen.dart';
import 'history_providers.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final history = ref.watch(cycleHistoryProvider(userId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: history.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Previous salary cycles will appear here after you manually reset a cycle.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final snapshot = history[index];
                final sortedCategories =
                    snapshot.categoryBreakdown.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value));

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CycleHistoryDetailScreen(snapshot: snapshot),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            theme.colorScheme.primary.withValues(alpha: 0.16),
                            const Color(0xFF1E1B28).withValues(alpha: 0.42),
                            const Color(0xFF1E1B28).withValues(alpha: 0.42),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${AppFormatters.formatDate(snapshot.cycleStartDate)} - ${AppFormatters.formatDate(snapshot.cycleEndDate)}',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${snapshot.transactionCount} transactions archived',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 16,
                            runSpacing: 10,
                            children: [
                              _HistoryMetric(
                                label: 'Expenses',
                                value: AppFormatters.formatCurrency(
                                  snapshot.totalExpenses,
                                ),
                              ),
                              _HistoryMetric(
                                label: 'Budget',
                                value: AppFormatters.formatCurrency(
                                  snapshot.cycleBudget,
                                ),
                              ),
                              _HistoryMetric(
                                label: 'Salary',
                                value: AppFormatters.formatCurrency(
                                  snapshot.cycleSalary,
                                ),
                              ),
                              _HistoryMetric(
                                label: 'Budget - Expenses',
                                value: AppFormatters.formatCurrency(
                                  snapshot.budgetMinusExpenses,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (sortedCategories.isNotEmpty) ...[
                            Text(
                              'Top categories',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: sortedCategories.take(4).map((entry) {
                                final style = CategoryStyles.of(entry.key);
                                return Chip(
                                  avatar: Icon(
                                    style.icon,
                                    size: 16,
                                    color: style.color,
                                  ),
                                  label: Text(
                                    '${entry.key}: ${AppFormatters.formatCurrency(entry.value)}',
                                  ),
                                  side: BorderSide(
                                    color: style.color.withValues(alpha: 0.18),
                                  ),
                                  backgroundColor: style.color.withValues(
                                    alpha: 0.08,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _HistoryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HistoryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
