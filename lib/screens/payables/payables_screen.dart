import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';

import '../../models/payable/payable_model.dart';
import '../../navigation/floating_glass_nav.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/storage/storage_providers.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/glass.dart';
import '../debts/widgets/debt_list_row.dart';
import 'providers/payables_providers.dart';
import 'widgets/payable_modal.dart';
import 'widgets/payable_settlement_modal.dart';

/// Payables — money you owe. Rendered inside the Debts tab.
class PayablesScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const PayablesScreen({super.key, this.embedded = false});

  @override
  ConsumerState<PayablesScreen> createState() => _PayablesScreenState();
}

class _PayablesScreenState extends ConsumerState<PayablesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(currentUserIdProvider) ?? '';
      ref.read(payablesProvider.notifier).fetchPayables(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final payablesState = ref.watch(payablesProvider);
    final payables = ref.watch(filteredPayablesProvider(userId));
    final total = ref.watch(totalPayablesProvider(userId));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Payables'), elevation: 0),
      body: payablesState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(payablesProvider.notifier).fetchPayables(userId),
              child: SlidableAutoCloseBehavior(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    14,
                    16,
                    16 + kNavBottomInset,
                  ),
                  children: [
                    GlassCard(
                      radius: 16,
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          cs.error.withValues(alpha: 0.16),
                          const Color(0xFF131318).withValues(alpha: 0.42),
                        ],
                      ),
                      border: Border.all(
                        color: cs.error.withValues(alpha: 0.25),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total you owe',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppFormatters.formatCurrency(total),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: cs.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (payables.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Text(
                            'You don\'t owe anything yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      ...payables.map((p) {
                        final status = payableDisplayStatus(p);
                        return DebtListRow(
                          key: ValueKey(p.id),
                          initial: p.toPerson.isNotEmpty
                              ? p.toPerson[0].toUpperCase()
                              : '?',
                          name: p.toPerson,
                          subtitle: _subtitle(p, status),
                          amount: AppFormatters.formatCurrency(
                            p.remainingAmount,
                          ),
                          amountColor: cs.error,
                          statusLabel: _statusLabel(status),
                          statusKind: _statusKind(status),
                          showPrimary: status != PayableDisplayStatus.paid,
                          primaryLabel: 'Settle',
                          primaryIcon: Icons.payments_rounded,
                          onPrimary: () =>
                              showPayableSettlementModal(context, payable: p),
                          onDelete: () => _confirmDelete(p),
                          onTap: () =>
                              showEditPayableModal(context, payable: p),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }

  String _subtitle(Payable p, PayableDisplayStatus status) {
    if (status == PayableDisplayStatus.partial) {
      return '${AppFormatters.formatCurrency(p.remainingAmount)} of '
          '${AppFormatters.formatCurrency(p.amount)} left';
    }
    final due = status == PayableDisplayStatus.overdue
        ? 'Overdue'
        : (status == PayableDisplayStatus.paid
              ? 'Settled'
              : 'Due ${DateFormat('MMM d').format(p.dueDate)}');
    return '${p.category} · $due';
  }

  String _statusLabel(PayableDisplayStatus status) => switch (status) {
    PayableDisplayStatus.paid => 'Paid',
    PayableDisplayStatus.overdue => 'Overdue',
    PayableDisplayStatus.partial => 'Partial',
    PayableDisplayStatus.pending => 'Due',
  };

  DebtStatusKind _statusKind(PayableDisplayStatus status) => switch (status) {
    PayableDisplayStatus.paid => DebtStatusKind.paid,
    PayableDisplayStatus.overdue => DebtStatusKind.overdue,
    PayableDisplayStatus.partial => DebtStatusKind.partial,
    PayableDisplayStatus.pending => DebtStatusKind.due,
  };

  Future<void> _confirmDelete(Payable payable) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete payable?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(payablesProvider.notifier).deletePayable(payable.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Payable deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            ref.read(payablesProvider.notifier).addPayable(payable);
          },
        ),
      ),
    );
  }
}
