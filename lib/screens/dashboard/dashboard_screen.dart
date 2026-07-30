import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/category_styles.dart';
import '../../models/expense/expense_model.dart';
import '../../navigation/floating_glass_nav.dart';
import '../../providers/ai_providers.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/budget/budget_providers.dart';
import '../../providers/cycle/cycle_providers.dart';
import '../../providers/debt/debt_providers.dart';
import '../../providers/storage/storage_providers.dart'
    show totalPayablesProvider;
import '../../providers/sync/sync_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/ai_text.dart';
import '../../widgets/common/glass.dart';
import '../ai_chat_screen.dart';
import '../settings/providers/settings_providers.dart';
import '../settings/settings_screen.dart';
import 'providers/dashboard_providers.dart';
import 'widgets/budget_settings_modal.dart';

/// Home tab — a calm, glass "cycle health" overview.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final dashboardState = ref.watch(dashboardProvider);
    final recentExpenses = ref.watch(recentExpensesProvider(userId));
    final aiSummary = ref.watch(dashboardAiSummaryProvider(userId));
    final monthlySpend = ref.watch(monthlySpendProvider(userId));
    final receivablesTotal = ref.watch(receivablesTotalProvider(userId));
    final payablesTotal = ref.watch(totalPayablesProvider(userId));
    final overdueDebtCount = ref.watch(overdueDebtCountProvider(userId));
    final budgetMetrics = ref.watch(budgetMetricsProvider(userId));
    final settings = ref.watch(settingsProvider);

    final categoryTotals = <String, double>{};
    for (final e in ref.watch(cycleExpensesProvider)) {
      if (e.userId != userId) continue;
      categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.amount;
    }
    final topCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final colorScheme = Theme.of(context).colorScheme;
    final calm = CalmColors.of(context);
    final cycleDay =
        DateTime.now().difference(settings.currentCycleStartDate).inDays + 1;

    final isWide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    final header = _Header(
      cycleDay: cycleDay,
      name: ref.watch(
        settingsProvider.select(
          (s) => s.displayName.isEmpty ? 'there' : s.displayName,
        ),
      ),
      isSyncing: ref.watch(syncProvider.select((s) => s.isSyncing)),
      onSync: () => ref.read(syncProvider.notifier).syncNow(),
    );
    final hero = _CycleHealthHero(
      metrics: budgetMetrics,
      monthlySpend: monthlySpend,
      aiSummary: aiSummary,
      onTap: () => showBudgetSettingsModal(context),
      // Desktop: the AI summary moves to its own sidebar card.
      showAi: !isWide,
    );
    final statTiles = Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Owed to you',
            value: AppFormatters.formatCurrency(receivablesTotal),
            valueColor: calm.positive,
            dotColor: calm.positive,
            sub: 'Receivables',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'You owe',
            value: AppFormatters.formatCurrency(payablesTotal),
            valueColor: colorScheme.error,
            dotColor: colorScheme.error,
            sub: overdueDebtCount > 0
                ? '$overdueDebtCount overdue'
                : 'Payables',
          ),
        ),
      ],
    );
    final categories = topCategories.isNotEmpty
        ? _CategoryBreakdown(categories: topCategories.take(5).toList())
        : null;
    final recent = _RecentCard(expenses: recentExpenses.take(5).toList());

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: dashboardState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(syncProvider.notifier).syncNow(),
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    isWide ? 24 : 16 + kNavBottomInset,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      const SizedBox(height: 18),
                      if (isWide)
                        // Desktop: hero + recent on the left, totals and
                        // categories in a right sidebar column.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: Column(
                                children: [
                                  hero,
                                  const SizedBox(height: 12),
                                  recent,
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  statTiles,
                                  if (categories != null) ...[
                                    const SizedBox(height: 12),
                                    categories,
                                  ],
                                  const SizedBox(height: 12),
                                  _AiInsightCard(aiSummary: aiSummary),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        hero,
                        const SizedBox(height: 12),
                        statTiles,
                        if (categories != null) ...[
                          const SizedBox(height: 12),
                          categories,
                        ],
                        const SizedBox(height: 12),
                        recent,
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Greeting + cycle-day chip + sync + AI-chat button + avatar (→ Settings).
class _Header extends StatelessWidget {
  final int cycleDay;
  final String name;
  final bool isSyncing;
  final VoidCallback onSync;

  const _Header({
    required this.cycleDay,
    required this.name,
    required this.isSyncing,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? 'Good morning,'
        : (hour < 17 ? 'Good afternoon,' : 'Good evening,');

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greet,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
          ),
          child: Text(
            'Cycle · day $cycleDay',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 9),
        isSyncing
            ? Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : _circleBtn(context, icon: Icons.sync_rounded, onTap: onSync),
        const SizedBox(width: 9),
        _circleBtn(
          context,
          icon: Icons.auto_awesome_rounded,
          tinted: true,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const AiChatScreen())),
        ),
        const SizedBox(width: 9),
        _circleBtn(
          context,
          icon: Icons.settings_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _circleBtn(
    BuildContext context, {
    IconData? icon,
    String? label,
    bool tinted = false,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tinted
              ? cs.primary.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest.withValues(alpha: 0.6),
          border: Border.all(
            color: tinted
                ? cs.primary.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: icon != null
            ? Icon(
                icon,
                size: 18,
                color: tinted ? cs.primary : cs.onSurfaceVariant,
              )
            : Center(
                child: Text(
                  label ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Glass hero: left-to-spend + budget ring + AI insight. Tap → budget settings.
class _CycleHealthHero extends StatelessWidget {
  final BudgetMetrics metrics;
  final double monthlySpend;
  final AsyncValue<String?> aiSummary;
  final VoidCallback onTap;

  /// Desktop shows the AI summary as its own sidebar card instead.
  final bool showAi;

  const _CycleHealthHero({
    required this.metrics,
    required this.monthlySpend,
    required this.aiSummary,
    required this.onTap,
    this.showAi = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasBudget = metrics.hasBudget;
    final over = hasBudget && metrics.remaining < 0;
    final percent = hasBudget ? metrics.percentSpent.clamp(0.0, 1.0) : 0.0;
    final headline = hasBudget
        ? (over ? metrics.remaining.abs() : metrics.remaining)
        : monthlySpend;
    final aiText = aiSummary.maybeWhen(
      data: (t) => (t == null || t.trim().isEmpty) ? null : t.trim(),
      orElse: () => null,
    );
    final aiLoading = aiSummary.isLoading;

    return GlassCard(
      onTap: onTap,
      radius: 22,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          cs.primary.withValues(alpha: 0.20),
          cs.primary.withValues(alpha: 0.04),
        ],
      ),
      border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasBudget
                          ? (over
                                ? 'Over budget this cycle'
                                : 'Left to spend this cycle')
                          : 'Spent this cycle',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppFormatters.formatCurrency(headline),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: over ? cs.error : cs.onSurface,
                      ),
                    ),
                    if (hasBudget) ...[
                      const SizedBox(height: 4),
                      Text(
                        'of ${AppFormatters.formatCurrency(metrics.budget)} budget · '
                        '${AppFormatters.formatCurrency(metrics.spent)} spent',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasBudget) _BudgetRing(percent: percent, over: over),
            ],
          ),
          if (showAi && (aiText != null || aiLoading)) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 12),
            _AiSummaryRow(aiText: aiText),
          ],
        ],
      ),
    );
  }
}

/// The ✦ icon + AI text (or its loading shimmer) — shared between the hero
/// (mobile) and the sidebar card (desktop).
class _AiSummaryRow extends StatelessWidget {
  final String? aiText;

  const _AiSummaryRow({required this.aiText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(Icons.auto_awesome_rounded, size: 14, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: aiText == null
              ? Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Analyzing your finances…',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                )
              : AiText(
                  aiText!,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
        ),
      ],
    );
  }
}

/// Desktop sidebar card housing the AI summary (mobile keeps it in the hero).
class _AiInsightCard extends StatelessWidget {
  final AsyncValue<String?> aiSummary;

  const _AiInsightCard({required this.aiSummary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aiText = aiSummary.maybeWhen(
      data: (t) => (t == null || t.trim().isEmpty) ? null : t.trim(),
      orElse: () => null,
    );
    if (aiText == null && !aiSummary.isLoading) {
      return const SizedBox.shrink();
    }
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          cs.primary.withValues(alpha: 0.14),
          cs.primary.withValues(alpha: 0.03),
        ],
      ),
      border: Border.all(color: cs.primary.withValues(alpha: 0.20)),
      child: _AiSummaryRow(aiText: aiText),
    );
  }
}

class _BudgetRing extends StatelessWidget {
  final double percent;
  final bool over;

  const _BudgetRing({required this.percent, required this.over});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ringColor = over ? cs.error : cs.primary;
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 7,
              valueColor: AlwaysStoppedAnimation(
                Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          SizedBox(
            width: 76,
            height: 76,
            child: CircularProgressIndicator(
              value: percent,
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(ringColor),
            ),
          ),
          Text(
            '${(percent * 100).round()}%',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Compact glass stat tile: label + big value + subtitle.
class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color? dotColor;
  final String? sub;

  const _StatTile({
    required this.label,
    required this.value,
    required this.valueColor,
    this.dotColor,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.4,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: valueColor,
              letterSpacing: -0.3,
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Where it's going" — top categories this cycle as labelled bars.
class _CategoryBreakdown extends StatelessWidget {
  final List<MapEntry<String, double>> categories;

  const _CategoryBreakdown({required this.categories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final max = categories.first.value;
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Where it's going",
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'this cycle',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...categories.map((entry) {
            final style = CategoryStyles.of(entry.key);
            final fraction = max > 0
                ? (entry.value / max).clamp(0.06, 1.0)
                : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 74,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: style.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 7,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation(style.color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    AppFormatters.formatCurrency(entry.value),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Recent transactions in a glass card.
class _RecentCard extends StatelessWidget {
  final List<Expense> expenses;

  const _RecentCard({required this.expenses});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMM dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'No transactions yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...expenses.map((e) {
              final style = CategoryStyles.of(e.category);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: style.color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(style.icon, size: 16, color: style.color),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.description ?? e.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${e.category} · ${_formatDate(e.date)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '-${AppFormatters.formatCurrency(e.amount)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
