import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/category_styles.dart';
import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/navigation_provider.dart';
import '../../models/expense/expense_model.dart';
import '../../navigation/floating_glass_nav.dart';
import '../../providers/ai_providers.dart';
import '../../providers/sms/sms_providers.dart';
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
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/glass.dart';
import '../ai_chat_screen.dart';
import '../expenses/widgets/add_expense_modal.dart';
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
      onTap: () => showBudgetSettingsModal(context),
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
                                  const _DetectedSmsCard(),
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
                        const SizedBox(height: 16),
                        _AiInsightCard(aiSummary: aiSummary, bottomGap: 12),
                        statTiles,
                        const _DetectedSmsCard(),
                        if (categories != null) ...[
                          const SizedBox(height: 12),
                          categories,
                        ],
                        const SizedBox(height: 16),
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

    return Row(
      children: [
        // Mockup greeting: one quiet line — the money hero below is the star.
        Expanded(
          child: Text(
            '${DateFormat('EEEE').format(DateTime.now())} · Hi $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        // Informational, not tappable — so no violet (locked accent rule).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A21),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Text(
            'Cycle · day $cycleDay',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
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
          icon: Icons.forum_rounded,
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

/// Mockup hero: the spent figure sits naked on the ground — Space Grotesk
/// with the paise dimmed — over a 'spent this cycle · budget X' caption and
/// a thin progress bar (red once over). Tap → budget settings.
class _CycleHealthHero extends StatelessWidget {
  final BudgetMetrics metrics;
  final double monthlySpend;
  final VoidCallback onTap;

  const _CycleHealthHero({
    required this.metrics,
    required this.monthlySpend,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasBudget = metrics.hasBudget;
    final over = hasBudget && metrics.remaining < 0;
    final money = AppFormatters.formatCurrency(
      hasBudget ? metrics.spent : monthlySpend,
    );
    final dot = money.lastIndexOf('.');
    final main = dot == -1 ? money : money.substring(0, dot);
    final paise = dot == -1 ? null : money.substring(dot);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: main,
                children: [
                  if (paise != null)
                    TextSpan(
                      text: paise,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0,
                      ),
                    ),
                ],
              ),
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasBudget
                  ? 'spent this cycle · budget ${AppFormatters.formatCurrency(metrics.budget)}'
                  : 'spent this cycle',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (hasBudget) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: metrics.percentSpent.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation(
                    over ? cs.error : cs.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
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

/// AI summary card — mockup style: solid card with a 2px violet left edge.
class _AiInsightCard extends StatelessWidget {
  final AsyncValue<String?> aiSummary;
  final double bottomGap;

  const _AiInsightCard({required this.aiSummary, this.bottomGap = 0});

  @override
  Widget build(BuildContext context) {
    final aiText = aiSummary.maybeWhen(
      data: (t) => (t == null || t.trim().isEmpty) ? null : t.trim(),
      orElse: () => null,
    );
    if (aiText == null && !aiSummary.isLoading) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: AccentEdgeCard(
        padding: const EdgeInsets.all(14),
        child: _AiSummaryRow(aiText: aiText),
      ),
    );
  }
}

/// Mockup's dashboard 'DETECTED · SMS' card: the first pending transaction
/// with inline Add / Dismiss, and a jump to Expenses when more are waiting.
class _DetectedSmsCard extends ConsumerWidget {
  const _DetectedSmsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = ref.watch(pendingTransactionsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final txn = pending.first;

    void add() {
      showAddExpenseModal(
        context,
        initialAmount: txn.amount,
        initialDate: txn.dateTime,
        sourceLabel:
            'Detected from SMS · ${DateFormat('EEE d MMM').format(txn.dateTime)}',
        onSaved: (expense) {
          ref
              .read(pendingTransactionsProvider.notifier)
              .markAdded(txn.id, expense.id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Added — synced to all devices')),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        radius: 12,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(
              pending.length == 1
                  ? 'Detected · SMS'
                  : 'Detected · ${pending.length} pending',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('EEE d MMM · h:mm a').format(txn.dateTime),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  AppFormatters.formatCurrency(txn.amount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _SmsAction(label: 'Add', primary: true, onTap: add),
                const SizedBox(width: 8),
                _SmsAction(
                  label: 'Dismiss',
                  onTap: () => ref
                      .read(pendingTransactionsProvider.notifier)
                      .dismiss(txn.id),
                ),
                const Spacer(),
                if (pending.length > 1)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => ref
                        .read(navigationProvider.notifier)
                        .navigateTo(NavigationTab.expenses),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        'View all',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmsAction extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _SmsAction({
    required this.label,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: primary
              ? cs.primary.withValues(alpha: 0.14)
              : const Color(0xFF1A1A21),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: primary
                ? cs.primary.withValues(alpha: 0.30)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: primary ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
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
      radius: 12,
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
                    fontFamily: 'JetBrains Mono',
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontSize: 10,
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
            // Spec: stat values are Space Grotesk 600.
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w600,
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
      radius: 12,
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

/// Mockup 'RECENT': mono header on the ground, each transaction its own
/// solid row card ('Name / Category · Method' + tabular amount).
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: FieldLabel('Recent'),
        ),
        if (expenses.isEmpty)
          GlassCard(
            radius: 12,
            padding: const EdgeInsets.symmetric(vertical: 22),
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
            final method = e.paymentMethod;
            final caption =
                '${e.category} · ${(method == null || method.isEmpty) ? _formatDate(e.date) : method}';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF131318),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
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
                          caption,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    AppFormatters.formatCurrency(e.amount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
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
