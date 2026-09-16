import '../../models/ai/dashboard_insight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../providers/update_providers.dart';
import '../../widgets/common/update_flow.dart';
import '../../services/storage/hive_service.dart';
import 'package:intl/intl.dart';

import '../../core/constants/category_styles.dart';
import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/navigation_provider.dart';
import '../../models/expense/expense_model.dart';
import '../../models/reminder/reminder_model.dart';
import '../../navigation/floating_glass_nav.dart';
import '../../providers/ai_providers.dart';
import '../../providers/sms/sms_providers.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/budget/budget_providers.dart';
import '../../providers/clock_provider.dart';
import '../../models/category/category_kinds.dart';
import '../../providers/categories/category_providers.dart';
import '../../providers/cycle/cycle_providers.dart';
import '../../providers/debt/debt_providers.dart';
import '../receivables/providers/receivables_providers.dart';
import '../../providers/storage/storage_providers.dart'
    show totalPayablesProvider;
import '../../providers/sync/sync_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/ai_text.dart';
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/glass.dart';
import '../ai_chat_screen.dart';
import '../cycle_recap_dialog.dart';
import '../expenses/utils/expense_helpers.dart';
import '../expenses/widgets/add_expense_modal.dart';
import '../settings/providers/reminder_providers.dart';
import '../settings/providers/settings_providers.dart';
import '../settings/settings_screen.dart';
import 'providers/dashboard_providers.dart';
import 'widgets/bills_due_card.dart';
import 'widgets/budget_settings_modal.dart';
import 'widgets/setup_checklist_card.dart';
import '../../widgets/common/top_notice.dart';
import '../../widgets/common/sync_feedback.dart';

/// Home tab — a calm, glass "cycle health" overview.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final dashboardState = ref.watch(dashboardProvider);
    final recentExpenses = ref.watch(recentExpensesProvider(userId));
    final aiSummary = ref.watch(dashboardAiSummaryProvider(userId));
    final receivablesTotal = ref.watch(receivablesTotalProvider(userId));
    final payablesTotal = ref.watch(totalPayablesProvider(userId));
    final overdueReceivableCount = ref
        .watch(receivablesStatsProvider(userId))
        .overdueCount;
    final overduePayableCount = ref.watch(overduePayablesCountProvider(userId));
    final budgetMetrics = ref.watch(budgetMetricsProvider(userId));
    final settings = ref.watch(settingsProvider);

    // Spending only — a SIP is not a category you overspent in, and a card
    // bill payment belongs to the purchases it settles, not to itself.
    final categoryTotals = <String, double>{};
    for (final e
        in ref
            .watch(cycleExpensesProvider)
            .where((e) => e.userId == userId)
            .spendable(ref.watch(categoryKindsProvider))) {
      categoryTotals[e.category] = (categoryTotals[e.category] ?? 0) + e.amount;
    }
    // A fully refunded category is not a bar; the cycle total still counts it.
    final topCategories =
        categoryTotals.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final colorScheme = Theme.of(context).colorScheme;
    final calm = CalmColors.of(context);
    final cycleDay =
        DateTime.now().difference(settings.currentCycleStartDate).inDays + 1;

    final isWide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    final header = _Header(
      cycleDay: cycleDay,
      weekday: DateFormat('EEEE').format(ref.watch(nowProvider)()),
      name: ref.watch(
        settingsProvider.select(
          (s) => s.displayName.isEmpty ? 'there' : s.displayName,
        ),
      ),
      isSyncing: ref.watch(syncProvider.select((s) => s.isSyncing)),
      onSync: () => syncWithFeedback(ref),
    );
    final hero = _CycleHealthHero(
      metrics: budgetMetrics,
      daysLeft: ref
          .watch(cycleEndProvider)
          .difference(ref.watch(nowProvider)())
          .inDays,
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
            // Each tile counts only its own side. The overdue figure used to
            // be receivables + payables combined and was printed under "You
            // owe", so a ₹0 payables tile read "2 overdue" when the two
            // overdue items were people owing the user.
            sub: overdueReceivableCount > 0
                ? '$overdueReceivableCount overdue'
                : 'Receivables',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'You owe',
            value: AppFormatters.formatCurrency(payablesTotal),
            valueColor: colorScheme.error,
            dotColor: colorScheme.error,
            sub: overduePayableCount > 0
                ? '$overduePayableCount overdue'
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
                      const _SyncStatusLine(),
                      const SizedBox(height: 18),
                      const _UpdatePrompt(),
                      const _CycleRollPrompt(),
                      const SetupChecklistCard(),
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
                                  const SizedBox(height: 16),
                                  const BillsDueCard(),
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
                        // Directly under the money: these are the things that
                        // move it, and the reason the bills figure above is
                        // still a reservation rather than a record.
                        const BillsDueCard(),
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
  final String weekday;
  final String name;
  final bool isSyncing;
  final VoidCallback onSync;

  const _Header({
    required this.cycleDay,
    required this.weekday,
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
        // The weekday is dropped before the name is: squeezed between the
        // cycle chip and three icon buttons, this used to ellipsize down to
        // "Hi ..." and greet nobody.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Text(
              constraints.maxWidth < 150 ? 'Hi $name' : '$weekday · Hi $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
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
/// The cycle in one glance: what is still yours to spend, what the bills have
/// taken, and — kept deliberately outside both — what went into investments or
/// merely moved between your own accounts.
///
/// The headline used to be "spent this cycle", which answered a question
/// nobody opens the app with. Rent made it look alarming in the first week and
/// harmless in the last. "Left to spend" is the number being asked for, and
/// the meter underneath shows where the rest of the budget went.
class _CycleHealthHero extends StatelessWidget {
  final BudgetMetrics metrics;

  /// Days until the cycle is expected to roll. Negative once it is overdue,
  /// which is a real state — the app never rolls a cycle on its own.
  final int daysLeft;
  final VoidCallback onTap;

  const _CycleHealthHero({
    required this.metrics,
    required this.daysLeft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasBudget = metrics.hasBudget;

    // Without a budget there is no "left", so the old headline is still the
    // only honest one.
    final headlineValue = hasBudget ? metrics.everydayLeft : metrics.spent;
    final headlineIsDeficit = hasBudget && metrics.everydayLeft < 0;
    final money = AppFormatters.formatCurrency(headlineValue.abs());
    final dot = money.lastIndexOf('.');
    final main = dot == -1 ? money : money.substring(0, dot);
    final paise = dot == -1 ? null : money.substring(dot);

    // A cycle nobody has rolled in months would otherwise print "234 days to
    // go", which is not a countdown anyone believes. Past 45 days the number
    // says nothing useful, so it says nothing.
    final showDays = daysLeft >= 0 && daysLeft <= 45;
    final caption = !hasBudget
        ? 'spent this cycle'
        : [
            headlineIsDeficit ? 'over your everyday budget' : 'left to spend',
            if (showDays && daysLeft > 1)
              '$daysLeft days to go'
            else if (showDays && daysLeft == 1)
              '1 day to go'
            else if (showDays && daysLeft == 0)
              'last day',
          ].join(' · ');

    return Semantics(
      button: true,
      label: hasBudget
          ? '${headlineIsDeficit ? 'Over by' : 'Left to spend'} $money of '
                '${AppFormatters.formatCurrency(metrics.everydayAllowance)} '
                'everyday. Bills '
                '${AppFormatters.formatCurrency(metrics.committedSpent)} of '
                '${AppFormatters.formatCurrency(metrics.committedReserved)}.'
          : 'Spent this cycle $money',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: headlineIsDeficit ? '-$main' : main,
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
                  color: headlineIsDeficit ? cs.error : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (hasBudget) ...[
                const SizedBox(height: 12),
                _BudgetMeter(metrics: metrics),
                const SizedBox(height: 12),
                _MeterLegend(metrics: metrics),
              ] else if (metrics.invested > 0 || metrics.income > 0) ...[
                const SizedBox(height: 12),
                _MeterLegend(metrics: metrics),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A bullet meter: bills, then everyday, then what is left — with a hairline
/// where the bills were *expected* to end.
///
/// Bills sit first because the bar then reads the way the money does:
/// unavoidable, then yours, then spare. Violet marks the everyday segment
/// because that is the part you control; the committed segment is deliberately
/// colourless.
class _BudgetMeter extends StatelessWidget {
  final BudgetMetrics metrics;

  const _BudgetMeter({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final budget = metrics.budget;
    if (budget <= 0) return const SizedBox.shrink();

    final committed = (metrics.committedSpent / budget).clamp(0.0, 1.0);
    final everyday = (metrics.everydaySpent / budget).clamp(
      0.0,
      1.0 - committed,
    );
    // Where the bills were planned to land. Hidden when it would sit under the
    // rounded end of the bar, where it reads as a rendering artefact.
    final mark = (metrics.committedReserved / budget).clamp(0.0, 1.0);
    final showMark = mark > 0.02 && mark < 0.98;
    final overspent = metrics.isOverAllowance || metrics.isOverCommitted;

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: width * committed * t,
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  Positioned(
                    left: width * committed * t,
                    top: 0,
                    bottom: 0,
                    width: width * everyday * t,
                    child: ColoredBox(color: overspent ? cs.error : cs.primary),
                  ),
                  if (showMark)
                    Positioned(
                      left: width * mark,
                      top: 0,
                      bottom: 0,
                      width: 1,
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.40),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The numbers behind the meter. A table so every amount ends on the same x —
/// ragged figures are what made the old category rows look accidental.
class _MeterLegend extends StatelessWidget {
  final BudgetMetrics metrics;

  const _MeterLegend({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final money = AppFormatters.formatCurrency;

    final rows = <TableRow>[
      if (metrics.hasBudget)
        _row(
          context,
          'Everyday',
          '${money(metrics.everydaySpent)} / ${money(metrics.everydayAllowance)}',
          valueColor: metrics.isOverAllowance ? cs.error : null,
        ),
      if (metrics.hasBudget && metrics.committedReserved > 0)
        _row(
          context,
          'Bills',
          '${money(metrics.committedSpent)} / ${money(metrics.committedReserved)}',
          note: metrics.committedPlanned > 0 ? 'still due' : null,
        ),
      if (metrics.income > 0)
        _row(
          context,
          'Came in',
          money(metrics.income),
          valueColor: calm.positive,
        ),
      if (metrics.invested > 0)
        _row(
          context,
          'Invested',
          money(metrics.invested),
          valueColor: calm.positive,
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(84),
        1: FlexColumnWidth(),
        2: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  TableRow _row(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
    String? note,
  }) {
    final theme = Theme.of(context);
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: FieldLabel(label),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(
            note ?? '',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
        Text(
          value,
          textAlign: TextAlign.right,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Asks — around the salary day — whether to start a new cycle, because the
/// cycle boundary is the thing every budget number is measured against and
/// nothing else moves it. Deliberately a question with an editable date:
/// salary lands early some months and late others, so the app must never
/// pick the date itself.
/// Tells the user a newer build exists, once per version.
///
/// Sideloaded apps have nothing to nag them, so an update used to be found only
/// by wandering into Settings. Dismissing records the version, so this stays
/// quiet until there's a genuinely newer one — and the Settings row remains the
/// way back to it.
class _UpdatePrompt extends ConsumerStatefulWidget {
  const _UpdatePrompt();

  @override
  ConsumerState<_UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends ConsumerState<_UpdatePrompt> {
  static const _key = 'updatePromptDismissedFor';

  String? _dismissedFor() {
    try {
      return Hive.box(kLocalPrefsBox).get(_key)?.toString();
    } catch (_) {
      return null;
    }
  }

  void _dismiss(String version) {
    try {
      Hive.box(kLocalPrefsBox).put(_key, version);
    } catch (_) {
      // Preference only — worst case it asks once more.
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final release = ref.watch(updateAvailableProvider).valueOrNull;
    if (!shouldPromptForUpdate(release, _dismissedFor())) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        radius: 12,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.system_update_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Lekha v${release!.version} is available',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _dismiss(release.version),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => runAppUpdate(context, release),
              child: const Text('Update'),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// An app alert as a point on the summary card, for when the AI summary is
/// not available — signed out, offline, or over the daily limit. The alerts
/// used to have a card of their own saying the same things as this one.
DashboardInsight _insightFromReminder(AppReminder reminder) => DashboardInsight(
  tone: switch (reminder.severity) {
    ReminderSeverity.danger => InsightTone.alert,
    ReminderSeverity.warning => InsightTone.warn,
    ReminderSeverity.success => InsightTone.good,
    ReminderSeverity.info => InsightTone.info,
  },
  text: reminder.message,
  target: switch (reminder.type) {
    ReminderType.overdueReceivable => InsightTarget.debts,
    ReminderType.upcomingRecurringExpense => InsightTarget.expenses,
    ReminderType.budgetWarning => InsightTarget.insights,
    ReminderType.monthlyBudgetPrompt => InsightTarget.insights,
    // A card bill is money owed, and Debts is where cards live.
    ReminderType.cardBillDue => InsightTarget.debts,
  },
);

class _CycleRollPrompt extends ConsumerWidget {
  const _CycleRollPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (!settings.cycleRollDue()) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final started = settings.currentCycleStartDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AccentEdgeCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start a new cycle?',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This one began ${DateFormat('d MMM').format(started)}'
              '${_cycleAge(started)}. '
              'Starting a new one archives it to History.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SmsActionPill(
                  label: 'Choose date',
                  primary: true,
                  onTap: () => _start(context, ref),
                ),
                const SizedBox(width: 8),
                SmsActionPill(
                  label: 'Not yet',
                  onTap: () =>
                      ref.read(settingsProvider.notifier).dismissCyclePrompt(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final suggested = settings.expectedCycleRollDate;
    final picked = await showDatePicker(
      context: context,
      // Defaults to the salary day, but the real credit date wins.
      initialDate: (suggested == null || suggested.isAfter(today))
          ? today
          : suggested,
      firstDate: settings.currentCycleStartDate,
      lastDate: today,
      helpText: 'Salary credited on',
    );
    if (picked == null || !context.mounted) return;
    await ref
        .read(settingsProvider.notifier)
        .resetSalaryCycle(startDate: picked);
    if (!context.mounted) return;
    await showCycleResetRecap(context, ref);
  }
}

/// AI summary card — mockup style: solid card with a 2px violet left edge.
/// The AI summary: two or three points, most urgent first, each with a dot
/// that says at a glance whether it needs doing (red), watching (amber) or is
/// fine (green), and a tap through to the screen it is about.
///
/// Deliberately a plain card. The accent rail and "AI" badge it had were
/// decoration; the label says where the words came from.
class _AiInsightCard extends ConsumerWidget {
  final AsyncValue<DashboardSummary?> aiSummary;
  final double bottomGap;

  const _AiInsightCard({required this.aiSummary, this.bottomGap = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = aiSummary.valueOrNull;
    // No AI answer, and none coming: fall back to the app's own alerts, so the
    // card still says what needs doing.
    final fallback = summary == null && !aiSummary.isLoading
        ? [
            for (final r in ref.watch(upcomingRemindersProvider).take(3))
              _insightFromReminder(r),
          ]
        : const <DashboardInsight>[];
    if (summary == null && !aiSummary.isLoading && fallback.isEmpty) {
      return const SizedBox.shrink();
    }
    final items = summary?.items ?? fallback;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final userId = ref.read(currentUserIdProvider) ?? localUserId;

    Color dot(InsightTone tone) => switch (tone) {
      InsightTone.alert => cs.error,
      InsightTone.warn => calm.warning,
      InsightTone.good => calm.positive,
      InsightTone.info => cs.onSurfaceVariant,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: GlassCard(
        radius: 12,
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FieldLabel(summary == null ? 'Needs attention' : 'AI summary'),
                if (summary != null)
                  Text(
                    ' · ${AppFormatters.getRelativeTime(summary.generatedAt).toLowerCase()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh summary',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: aiSummary.isLoading
                      ? null
                      : () =>
                            ref.invalidate(dashboardAiSummaryProvider(userId)),
                ),
              ],
            ),
            if (summary == null && aiSummary.isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 10, 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Reading this cycle…',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              for (final item in items)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: item.target == null
                      ? null
                      : () => ref.read(navigationProvider.notifier).navigateTo(
                          switch (item.target!) {
                            InsightTarget.debts => NavigationTab.debts,
                            InsightTarget.expenses => NavigationTab.expenses,
                            InsightTarget.insights => NavigationTab.insights,
                          },
                        ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 7, 4, 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          // Centres the dot on the first line of text.
                          padding: const EdgeInsets.only(top: 7),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: dot(item.tone),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AiText(
                            item.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.4,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 24,
                          child: item.target == null
                              ? null
                              : Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
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
            '${detectionSource(txn)} · '
            '${DateFormat('EEE d MMM').format(txn.dateTime)}',
        onSaved: (expense) {
          ref
              .read(pendingTransactionsProvider.notifier)
              .markAdded(txn.id, expense.id);
          showNotice('✓ Added — synced to all devices');
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
                  ? 'Detected'
                  : 'Detected · ${pending.length} pending',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      ?txn.merchant,
                      DateFormat('EEE d MMM · h:mm a').format(txn.dateTime),
                    ].join(' · '),
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
                SmsActionPill(label: 'Add', primary: true, onTap: add),
                const SizedBox(width: 8),
                SmsActionPill(
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
              // Mono, like every other section header (RECENT, DETECTED…).
              const FieldLabel("Where it's going"),
              Text(
                'this cycle',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          // 12 above the first bar, with the row's own 4.5 of padding.
          const SizedBox(height: 7.5),
          // A table, not a row per category: the amount column is as wide as
          // the widest amount, so every track starts and ends at the same x.
          // As rows, each track was squeezed by its own amount's width, and
          // "₹5,120.90" visibly shortened its bar next to "₹456".
          Table(
            columnWidths: const {
              // Fits the longest built-in category ("Entertainment") without
              // ellipsis, plus the gap before the track.
              0: FixedColumnWidth(113),
              1: FlexColumnWidth(),
              2: IntrinsicColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              for (final entry in categories) _categoryRow(context, entry, max),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _categoryRow(
    BuildContext context,
    MapEntry<String, double> entry,
    double max,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = CategoryStyles.of(entry.key);
    final fraction = max > 0 ? (entry.value / max).clamp(0.06, 1.0) : 0.0;
    const cell = EdgeInsets.symmetric(vertical: 4.5);
    return TableRow(
      children: [
        Padding(
          padding: cell.copyWith(right: 9),
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
        Padding(
          padding: cell,
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
        Padding(
          padding: cell.copyWith(left: 9),
          child: Text(
            AppFormatters.formatCurrency(entry.value),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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
            final method = expensePaymentMethod(e);
            final caption = '${e.category} · ${method ?? _formatDate(e.date)}';
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

/// " — 3 days ago", or nothing at all on the day it started.
///
/// The old line said "1 days ago", and "0 days ago" for a cycle begun this
/// morning, which reads like a bug even though the number was right.
String _cycleAge(DateTime started) {
  final days = DateTime.now().difference(started).inDays;
  if (days <= 0) return ', today';
  return ' — $days ${AppFormatters.plural(days, 'day', 'days')} ago';
}

/// A line under the header, shown only when there is something to say: the
/// stage while a sync runs, and the reason plus a way back when one failed.
/// Silence the rest of the time — a permanent "everything is fine" banner is
/// just something to learn to ignore.
class _SyncStatusLine extends ConsumerWidget {
  const _SyncStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    return SyncStatusLine(
      isSyncing: sync.isSyncing,
      status: sync.status,
      error: sync.error,
      onRetry: () => syncWithFeedback(ref),
    );
  }
}

/// A line under the header, shown only when there is something to say: the
/// stage while a sync runs, and the reason plus a way back when one failed.
/// Silence the rest of the time — a permanent "everything is fine" banner is
/// just something to learn to ignore.
///
/// Takes plain values rather than reading the provider so it can be rendered
/// in a test; the state it shows only exists mid-sync on a signed-in account,
/// which is not reachable from a harness.
class SyncStatusLine extends StatelessWidget {
  final bool isSyncing;
  final String status;
  final String? error;
  final VoidCallback onRetry;

  const SyncStatusLine({
    super.key,
    required this.isSyncing,
    required this.status,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final failed = !isSyncing && error != null;
    if (!isSyncing && !failed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          if (isSyncing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Icon(Icons.error_outline_rounded, size: 14, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isSyncing
                  ? (status.isEmpty ? 'Syncing…' : status)
                  : 'Sync failed — your data is safe on this device',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: failed ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ),
          if (failed)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
