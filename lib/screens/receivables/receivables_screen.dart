import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';

import '../../models/receivable/receivable_model.dart';
import '../../navigation/floating_glass_nav.dart';
import '../../providers/auth/auth_provider.dart';
import '../../providers/storage/storage_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters/formatters.dart';
import '../../widgets/common/glass.dart';
import '../debts/widgets/debt_list_row.dart';
import 'providers/receivables_providers.dart';
import 'widgets/receivable_modal.dart';

/// Receivables — money owed to you. Rendered inside the Debts tab.
class ReceivablesScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const ReceivablesScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends ConsumerState<ReceivablesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(currentUserIdProvider) ?? '';
      ref.read(receivablesProvider.notifier).fetchReceivables(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final receivablesState = ref.watch(receivablesProvider);
    final receivables = ref.watch(filteredReceivablesProvider(userId));
    final total = ref.watch(totalReceivablesProvider(userId));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Receivables'), elevation: 0),
      body: receivablesState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(receivablesProvider.notifier)
                  .fetchReceivables(userId),
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
                          calm.positive.withValues(alpha: 0.16),
                          const Color(0xFF1E1B28).withValues(alpha: 0.42),
                        ],
                      ),
                      border: Border.all(
                        color: calm.positive.withValues(alpha: 0.25),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total owed to you',
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
                              color: calm.positive,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (receivables.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Text(
                            'Nothing owed to you yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      ...receivables.map((r) {
                        final status = receivableStatus(r);
                        return DebtListRow(
                          key: ValueKey(r.id),
                          initial: r.fromPerson.isNotEmpty
                              ? r.fromPerson[0].toUpperCase()
                              : '?',
                          name: r.fromPerson,
                          subtitle: _subtitle(r, status),
                          amount: AppFormatters.formatCurrency(r.amount),
                          amountColor: calm.positive,
                          statusLabel: _statusLabel(status),
                          statusKind: _statusKind(status),
                          showPrimary: status != ReceivableStatus.paid,
                          primaryLabel: 'Received',
                          primaryIcon: Icons.check_rounded,
                          onPrimary: () => _markPaid(r),
                          onDelete: () => _confirmDelete(r),
                          onTap: () =>
                              showEditReceivableModal(context, receivable: r),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }

  String _subtitle(Receivable r, ReceivableStatus status) {
    final base = switch (status) {
      ReceivableStatus.paid => 'Received',
      ReceivableStatus.overdue => 'Overdue',
      ReceivableStatus.pending =>
        'Due ${DateFormat('MMM d').format(r.dueDate)}',
    };
    final note = r.description?.trim();
    return (note == null || note.isEmpty) ? base : '$base · $note';
  }

  String _statusLabel(ReceivableStatus status) => switch (status) {
    ReceivableStatus.paid => 'Paid',
    ReceivableStatus.overdue => 'Overdue',
    ReceivableStatus.pending => 'Due',
  };

  DebtStatusKind _statusKind(ReceivableStatus status) => switch (status) {
    ReceivableStatus.paid => DebtStatusKind.paid,
    ReceivableStatus.overdue => DebtStatusKind.overdue,
    ReceivableStatus.pending => DebtStatusKind.due,
  };

  Future<void> _markPaid(Receivable receivable) async {
    await ref
        .read(receivablesProvider.notifier)
        .markReceivablePaid(receivable.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${receivable.fromPerson} marked as received')),
    );
  }

  Future<void> _confirmDelete(Receivable receivable) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete receivable?'),
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

    await ref
        .read(receivablesProvider.notifier)
        .deleteReceivable(receivable.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Receivable deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            ref.read(receivablesProvider.notifier).addReceivable(receivable);
          },
        ),
      ),
    );
  }
}
