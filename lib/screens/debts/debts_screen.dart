import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/floating_glass_nav.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/share/share_providers.dart';
import '../../providers/storage/storage_providers.dart'
    show totalPayablesProvider, totalReceivablesProvider;
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/glass.dart';
import 'person_ledger_screen.dart';
import 'providers/people_balance_providers.dart';
import 'widgets/add_debt_sheet.dart';
import 'widgets/group_sheet.dart';

/// Debts — one netted balance per person. Tap someone to see the full ledger
/// of what you owe each other (inline pane on desktop, pushed on mobile).
class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  /// Desktop master-detail: the person whose ledger fills the right pane.
  String? _selectedPerson;

  @override
  void initState() {
    super.initState();
    // Opening this tab is the moment someone wants to know whether a guest
    // added anything — worth not making them wait out the 60s poll.
    Future.microtask(() => ref.read(sharedInboxProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final people = ref.watch(peopleBalancesProvider);
    final groups = ref.watch(sharedInboxProvider).groups;
    final owed = ref.watch(totalReceivablesProvider(userId));
    final owe = ref.watch(totalPayablesProvider(userId));
    final isWide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    final list = ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        isWide ? 24 : 16 + kNavBottomInset,
      ),
      children: [
        Text(
          'Debts',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _TotalBanner(
                label: 'Owed to you',
                value: owed,
                color: calm.positive,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TotalBanner(
                label: 'You owe',
                value: owe,
                color: cs.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 48, 0, 24),
            child: Center(
              child: Text(
                'No open debts.\nSplit a bill, or add one below.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          )
        else ...[
          const FieldLabel('People'),
          const SizedBox(height: 10),
          ...people.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PersonRow(balance: p, onTap: () => _openPerson(p.name)),
            ),
          ),
        ],
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 20),
          const FieldLabel('Groups'),
          const SizedBox(height: 10),
          ...groups.map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GroupRow(
                group: g,
                waiting: ref.watch(sharedInboxProvider).forSpace(g.id).length,
                onTap: () => showGroupSheet(context, g),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showNewGroupSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Center(
              child: Text(
                '+ New group',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Outside the empty check on purpose: this is the only add-a-debt
        // entry point, and it used to live inside the `else`, so settling your
        // last debt left no way to record another one. A FAB isn't the answer
        // either — it would land on the bottom bar's centre button, and two
        // violet circles doing different things read as a bug.
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showAddDebtSheet(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Center(
              child: Text(
                '+ Add a debt',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: list),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 16, 24),
                      child: _selectedPerson == null
                          ? GlassCard(
                              radius: 12,
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(
                                  'Select a person to see your ledger',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : PersonLedgerScreen(person: _selectedPerson!),
                    ),
                  ),
                ],
              )
            : list,
      ),
    );
  }

  void _openPerson(String name) {
    if (MediaQuery.sizeOf(context).width >= kWideBreakpoint) {
      setState(() => _selectedPerson = name);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PersonLedgerScreen(person: name)),
    );
  }
}

class _TotalBanner extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _TotalBanner({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      radius: 12,
      padding: const EdgeInsets.all(14),
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontFamily: 'JetBrains Mono',
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppFormatters.formatCurrency(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  final PersonBalance balance;
  final VoidCallback onTap;

  const _PersonRow({required this.balance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final net = balance.net;
    final settled = net.abs() < 0.01;
    final color = settled
        ? cs.onSurfaceVariant
        : (net > 0 ? calm.positive : cs.error);
    final initial = balance.name.trim().isEmpty
        ? '?'
        : balance.name.trim()[0].toUpperCase();

    final subtitle = [
      '${balance.openCount} ${balance.openCount == 1 ? 'item' : 'items'}',
      if (balance.hasOverdue) 'overdue',
    ].join(' · ');

    return GlassCard(
      onTap: onTap,
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balance.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: balance.hasOverdue ? cs.error : cs.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                settled
                    ? AppFormatters.formatCurrency(0)
                    : AppFormatters.formatCurrency(net.abs()),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                settled ? 'settled' : (net > 0 ? 'owes you' : 'you owe'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A group in the people list. Its balances live on the shared page, so this
/// only says how many people are in it and whether anything is waiting.
class _GroupRow extends StatelessWidget {
  final SharedGroup group;
  final int waiting;
  final VoidCallback onTap;

  const _GroupRow({
    required this.group,
    required this.waiting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassCard(
      radius: 12,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.group_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${group.members.length} '
                  '${group.members.length == 1 ? 'person' : 'people'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (waiting > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$waiting waiting',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
