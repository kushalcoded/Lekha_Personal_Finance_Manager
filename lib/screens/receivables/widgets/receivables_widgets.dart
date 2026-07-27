import 'package:flutter/material.dart';

import '../../../models/receivable/receivable_model.dart';
import '../../../utils/formatters/formatters.dart';
import '../providers/receivables_providers.dart';

class ReceivablesStatsHeader extends StatelessWidget {
  final ReceivablesStats stats;

  const ReceivablesStatsHeader({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cards = [
      _ReceivableStatCard(
        label: 'Total Owed',
        value: AppFormatters.formatCurrency(stats.totalOwed),
        icon: Icons.account_balance_wallet_rounded,
        accentColor: colorScheme.primary,
      ),
      _ReceivableStatCard(
        label: 'Collected',
        value: AppFormatters.formatCurrency(stats.collectedAmount),
        icon: Icons.check_circle_rounded,
        accentColor: colorScheme.tertiary,
      ),
      _ReceivableStatCard(
        label: 'Overdue',
        value: stats.overdueCount.toString(),
        icon: Icons.warning_amber_rounded,
        accentColor: colorScheme.error,
      ),
      _ReceivableStatCard(
        label: 'Active',
        value: stats.activeReceivables.toString(),
        icon: Icons.schedule_rounded,
        accentColor: colorScheme.secondary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final aspectRatio = columns == 1 ? 3.4 : 2.5;

        return GridView.builder(
          itemCount: cards.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) => cards[index],
        );
      },
    );
  }
}

class _ReceivableStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  const _ReceivableStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReceivableCard extends StatelessWidget {
  final Receivable receivable;
  final ReceivableStatus status;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ReceivableCard({
    super.key,
    required this.receivable,
    required this.status,
    required this.onMarkPaid,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColor(colorScheme);
    final isPaid = status == ReceivableStatus.paid;
    final isOverdue = status == ReceivableStatus.overdue;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isPaid
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : colorScheme.surface,
        border: Border.all(
          color: isOverdue
              ? colorScheme.error.withValues(alpha: 0.36)
              : colorScheme.outline.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final details = _ReceivableDetails(
            receivable: receivable,
            status: status,
            statusColor: statusColor,
          );
          final actions = _ReceivableActions(
            isPaid: isPaid,
            onMarkPaid: onMarkPaid,
            onEdit: onEdit,
            onDelete: onDelete,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

  Color _statusColor(ColorScheme colorScheme) {
    switch (status) {
      case ReceivableStatus.overdue:
        return colorScheme.error;
      case ReceivableStatus.paid:
        return colorScheme.tertiary;
      case ReceivableStatus.pending:
        return colorScheme.primary;
    }
  }
}

class _ReceivableDetails extends StatelessWidget {
  final Receivable receivable;
  final ReceivableStatus status;
  final Color statusColor;

  const _ReceivableDetails({
    required this.receivable,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPaid = status == ReceivableStatus.paid;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(_statusIcon(), color: statusColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      receivable.fromPerson,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: isPaid ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppFormatters.formatCurrency(receivable.amount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isPaid
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusPill(label: _statusLabel(), color: statusColor),
                  Text(
                    'Due ${AppFormatters.formatDate(receivable.dueDate, format: 'MMM dd, yyyy')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if ((receivable.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  receivable.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  IconData _statusIcon() {
    switch (status) {
      case ReceivableStatus.overdue:
        return Icons.priority_high_rounded;
      case ReceivableStatus.paid:
        return Icons.check_rounded;
      case ReceivableStatus.pending:
        return Icons.schedule_rounded;
    }
  }

  String _statusLabel() {
    switch (status) {
      case ReceivableStatus.overdue:
        return 'Overdue';
      case ReceivableStatus.paid:
        return 'Paid';
      case ReceivableStatus.pending:
        return 'Pending';
    }
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReceivableActions extends StatelessWidget {
  final bool isPaid;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReceivableActions({
    required this.isPaid,
    required this.onMarkPaid,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 6,
      children: [
        if (!isPaid)
          IconButton.filledTonal(
            onPressed: onMarkPaid,
            icon: const Icon(Icons.check_rounded),
            tooltip: 'Mark paid',
          ),
        IconButton(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded),
          tooltip: 'Edit',
        ),
        IconButton(
          onPressed: onDelete,
          icon: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
          tooltip: 'Delete',
        ),
      ],
    );
  }
}

class ReceivablesFilterBar extends StatelessWidget {
  final ReceivableStatusFilter selectedFilter;
  final ValueChanged<ReceivableStatusFilter> onChanged;

  const ReceivablesFilterBar({
    super.key,
    required this.selectedFilter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ReceivableStatusFilter.values.map((filter) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_filterLabel(filter)),
              selected: selectedFilter == filter,
              onSelected: (_) => onChanged(filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _filterLabel(ReceivableStatusFilter filter) {
    switch (filter) {
      case ReceivableStatusFilter.all:
        return 'All';
      case ReceivableStatusFilter.pending:
        return 'Pending';
      case ReceivableStatusFilter.paid:
        return 'Paid';
      case ReceivableStatusFilter.overdue:
        return 'Overdue';
    }
  }
}

class EmptyReceivablesState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onAddPressed;

  const EmptyReceivablesState({
    super.key,
    this.title = 'No receivables yet',
    this.message = 'Track money owed to you',
    required this.onAddPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.7,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.handshake_rounded,
                size: 28,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAddPressed,
              icon: const Icon(Icons.add),
              label: const Text('Add Receivable'),
            ),
          ],
        ),
      ),
    );
  }
}
