import 'package:flutter/material.dart';

import '../../../core/constants/category_styles.dart';
import '../../../models/payable/payable_model.dart';
import '../../../utils/formatters/formatters.dart';
import '../providers/payables_providers.dart';

class PayablesStatsHeader extends StatelessWidget {
  final PayablesStats stats;

  const PayablesStatsHeader({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cards = [
      _PayableStatCard(
        label: 'Total Owed',
        value: AppFormatters.formatCurrency(stats.totalOwed),
        icon: Icons.credit_card_rounded,
        accentColor: colorScheme.error,
      ),
      _PayableStatCard(
        label: 'Settled',
        value: AppFormatters.formatCurrency(stats.totalSettled),
        icon: Icons.check_circle_rounded,
        accentColor: colorScheme.tertiary,
      ),
      _PayableStatCard(
        label: 'Overdue',
        value: stats.overdueCount.toString(),
        icon: Icons.warning_amber_rounded,
        accentColor: colorScheme.error,
      ),
      _PayableStatCard(
        label: 'Active',
        value: stats.activeCount.toString(),
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

class _PayableStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  const _PayableStatCard({
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

class PayablesFilterBar extends StatelessWidget {
  final PayableStatusFilter selectedFilter;
  final ValueChanged<PayableStatusFilter> onChanged;

  const PayablesFilterBar({
    super.key,
    required this.selectedFilter,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: PayableStatusFilter.values.map((filter) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: filter == selectedFilter,
              label: Text(_label(filter)),
              onSelected: (_) => onChanged(filter),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _label(PayableStatusFilter filter) {
    switch (filter) {
      case PayableStatusFilter.all:
        return 'All';
      case PayableStatusFilter.pending:
        return 'Pending';
      case PayableStatusFilter.partial:
        return 'Partial';
      case PayableStatusFilter.paid:
        return 'Paid';
      case PayableStatusFilter.overdue:
        return 'Overdue';
    }
  }
}

class PayableCard extends StatelessWidget {
  final Payable payable;
  final PayableDisplayStatus status;
  final VoidCallback onSettle;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onHistory;

  const PayableCard({
    super.key,
    required this.payable,
    required this.status,
    required this.onSettle,
    required this.onMarkPaid,
    required this.onEdit,
    required this.onDelete,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColor(colorScheme);
    final style = CategoryStyles.of(payable.category);
    final isPaid = status == PayableDisplayStatus.paid;

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
          color: status == PayableDisplayStatus.overdue
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
          final compact = constraints.maxWidth < 540;
          final details = _PayableDetails(
            payable: payable,
            status: status,
            statusColor: statusColor,
            categoryStyle: style,
          );
          final actions = _PayableActions(
            isPaid: isPaid,
            onSettle: onSettle,
            onMarkPaid: onMarkPaid,
            onEdit: onEdit,
            onDelete: onDelete,
            onHistory: onHistory,
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
      case PayableDisplayStatus.overdue:
        return colorScheme.error;
      case PayableDisplayStatus.paid:
        return colorScheme.tertiary;
      case PayableDisplayStatus.partial:
        return colorScheme.secondary;
      case PayableDisplayStatus.pending:
        return colorScheme.primary;
    }
  }
}

class _PayableDetails extends StatelessWidget {
  final Payable payable;
  final PayableDisplayStatus status;
  final Color statusColor;
  final CategoryStyle categoryStyle;

  const _PayableDetails({
    required this.payable,
    required this.status,
    required this.statusColor,
    required this.categoryStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPaid = status == PayableDisplayStatus.paid;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: categoryStyle.tint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(categoryStyle.icon, color: categoryStyle.color, size: 22),
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
                      payable.toPerson,
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
                    AppFormatters.formatCurrency(payable.remainingAmount),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isPaid
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Total ${AppFormatters.formatCurrency(payable.amount)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusPill(label: _statusLabel(), color: statusColor),
                  _StatusPill(
                    label: payable.category,
                    color: categoryStyle.color,
                  ),
                  Text(
                    'Due ${AppFormatters.formatDate(payable.dueDate, format: 'MMM dd, yyyy')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if ((payable.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  payable.notes!,
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

  String _statusLabel() {
    switch (status) {
      case PayableDisplayStatus.overdue:
        return 'Overdue';
      case PayableDisplayStatus.paid:
        return 'Paid';
      case PayableDisplayStatus.partial:
        return 'Partial';
      case PayableDisplayStatus.pending:
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

class _PayableActions extends StatelessWidget {
  final bool isPaid;
  final VoidCallback onSettle;
  final VoidCallback onMarkPaid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onHistory;

  const _PayableActions({
    required this.isPaid,
    required this.onSettle,
    required this.onMarkPaid,
    required this.onEdit,
    required this.onDelete,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (!isPaid)
          FilledButton.tonal(onPressed: onSettle, child: const Text('Settle')),
        if (!isPaid)
          TextButton(onPressed: onMarkPaid, child: const Text('Mark paid')),
        TextButton(onPressed: onHistory, child: const Text('History')),
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
