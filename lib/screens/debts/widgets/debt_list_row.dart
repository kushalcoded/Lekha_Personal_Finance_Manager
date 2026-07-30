import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../widgets/common/glass.dart';

enum DebtStatusKind { due, overdue, paid, partial }

/// A glass debt row (person, amount, status chip) with swipe-to-reveal
/// actions: a primary action (mark received / settle) and delete.
class DebtListRow extends StatelessWidget {
  final String initial;
  final String name;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final String statusLabel;
  final DebtStatusKind statusKind;
  final bool showPrimary;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const DebtListRow({
    super.key,
    required this.initial,
    required this.name,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
    required this.statusLabel,
    required this.statusKind,
    required this.onPrimary,
    required this.onDelete,
    this.showPrimary = true,
    this.primaryLabel = 'Done',
    this.primaryIcon = Icons.check_rounded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: showPrimary ? 0.5 : 0.28,
          children: [
            if (showPrimary)
              SlidableAction(
                onPressed: (_) => onPrimary(),
                backgroundColor: const Color(0xFF5FBE93),
                foregroundColor: Colors.white,
                icon: primaryIcon,
                label: primaryLabel,
                borderRadius: BorderRadius.circular(14),
              ),
            SlidableAction(
              onPressed: (_) => onDelete(),
              backgroundColor: cs.error,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              borderRadius: BorderRadius.circular(14),
            ),
          ],
        ),
        child: GlassCard(
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
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
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
                    amount,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _StatusChip(label: statusLabel, kind: statusKind),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final DebtStatusKind kind;

  const _StatusChip({required this.label, required this.kind});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (kind) {
      DebtStatusKind.overdue => (
        const Color(0xFFE27C71),
        const Color(0xFFE27C71),
      ),
      DebtStatusKind.paid => (const Color(0xFF5FBE93), const Color(0xFF5FBE93)),
      DebtStatusKind.partial => (
        const Color(0xFFD7A24C),
        const Color(0xFFD7A24C),
      ),
      DebtStatusKind.due => (
        Theme.of(context).colorScheme.onSurfaceVariant,
        Colors.white,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: kind == DebtStatusKind.due ? 0.06 : 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: fg,
        ),
      ),
    );
  }
}
