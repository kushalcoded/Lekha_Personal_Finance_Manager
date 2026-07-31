import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/floating_glass_nav.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/storage/storage_providers.dart'
    show totalPayablesProvider, totalReceivablesProvider;
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/glass.dart';
import '../payables/widgets/payable_modal.dart';
import '../receivables/widgets/receivable_modal.dart';
import 'person_ledger_screen.dart';
import 'providers/people_balance_providers.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final people = ref.watch(peopleBalancesProvider);
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
            padding: const EdgeInsets.only(top: 60),
            child: Center(
              child: Text(
                'No open debts.\nSplit a bill or tap + to add one.',
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
          // Mockup's inline add row (the FAB stays for thumb reach).
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAddChooser(context),
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
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: Padding(
        // Lift the add button clear above the floating navigation bar (which
        // doesn't exist on wide screens).
        padding: EdgeInsets.only(bottom: isWide ? 0 : kNavBottomInset - 36),
        child: FloatingActionButton(
          onPressed: () => _showAddChooser(context),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          tooltip: 'Add a debt',
          child: const Icon(Icons.add_rounded),
        ),
      ),
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

  void _showAddChooser(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF131318),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.south_west_rounded),
              title: const Text('Someone owes me'),
              onTap: () {
                Navigator.of(ctx).pop();
                showAddReceivableModal(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.north_east_rounded),
              title: const Text('I owe someone'),
              onTap: () {
                Navigator.of(ctx).pop();
                showAddPayableModal(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
