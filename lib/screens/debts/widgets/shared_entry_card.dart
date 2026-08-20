import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/share/shared_entry.dart';
import '../../../providers/share/share_providers.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/form_bits.dart';
import '../../../widgets/common/glass.dart';

/// Something a guest did on a shared page, waiting on a decision.
///
/// Styled as the detected-SMS card, because it is the same promise: nothing
/// reached the ledger yet, and one tap either way settles it.
class SharedEntryCard extends StatelessWidget {
  final SharedEntry entry;
  final String ownerName;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const SharedEntryCard({
    super.key,
    required this.entry,
    required this.ownerName,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headline = entry.isSettlement
        ? 'Settling up'
        : (entry.note ?? 'Shared expense');

    return GlassCard(
      radius: 12,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                AppFormatters.formatCurrency(entry.total),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${entry.personName} · '
            '${DateFormat('MMM d').format(entry.occurredOn)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sharedEntryEffect(entry, ownerName: ownerName),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SmsActionPill(
                  label: 'Add',
                  primary: true,
                  onTap: onAccept,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmsActionPill(label: 'Dismiss', onTap: onDismiss),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A guest asking the person who shared the link to reset their PIN. Only that
/// person can — there is no administrator to escalate to.
class PinResetCard extends StatelessWidget {
  final PinResetRequest request;
  final VoidCallback onAllow;
  final VoidCallback onDismiss;

  const PinResetCard({
    super.key,
    required this.request,
    required this.onAllow,
    required this.onDismiss,
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
        children: [
          Text(
            '${request.name} forgot their PIN',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Allowing this lets them pick a new one next time they open the '
            'link, and signs them out everywhere else.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SmsActionPill(
                  label: 'Allow reset',
                  primary: true,
                  onTap: onAllow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmsActionPill(label: 'Not now', onTap: onDismiss),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
