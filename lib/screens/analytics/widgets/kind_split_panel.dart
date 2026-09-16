import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/formatters/formatters.dart';
import '../models/analytics_models.dart';

/// How much of the money was actually a choice.
///
/// The category pie ranks categories, so rent and restaurants sit side by side
/// as two slices of equal standing — and rent wins every month, which is why
/// the screen used to tell you the same thing forever. A cycle that is
/// four-fifths bills reads completely differently from one that is four-fifths
/// eating out, and that is the number worth pulling out on its own.
///
/// Money that merely moved — investments, card bills, income — is listed
/// underneath rather than drawn, because it is not part of the same whole.
class KindSplitPanel extends StatelessWidget {
  final KindSplit split;

  const KindSplitPanel({super.key, required this.split});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final calm = CalmColors.of(context);
    final money = AppFormatters.formatCurrency;
    final hasSpend = split.spent > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasSpend) ...[
          Text.rich(
            TextSpan(
              text: '${(split.committedShare * 100).round()}%',
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
              children: [
                TextSpan(
                  text: ' of your spending was bills',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Bills first, as on Home: unavoidable, then yours. Violet marks the
          // part you decide about.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              // Loose constraints from the Column would let the Row shrink to
              // nothing — Expanded children have no width to divide.
              width: double.infinity,
              height: 8,
              child: Row(
                // A ColoredBox with no child takes the smallest size it is
                // allowed, and Row's default centre alignment allows zero —
                // so without this the bar is full width and no height at all.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: (split.committedShare * 1000).round().clamp(0, 1000),
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  Expanded(
                    flex: (split.everydayShare * 1000).round().clamp(0, 1000),
                    child: ColoredBox(color: cs.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _row(
            context,
            'Bills',
            money(split.committed),
            note: '${(split.committedShare * 100).round()}%',
            swatch: Colors.white.withValues(alpha: 0.28),
          ),
          _row(
            context,
            'Everyday',
            money(split.everyday),
            note: '${(split.everydayShare * 100).round()}%',
            swatch: cs.primary,
          ),
        ],
        // Money that left, or arrived, without being spending. Plain rows,
        // because they are not slices of the bar above.
        if (split.invested > 0 || split.moved > 0 || split.income > 0) ...[
          if (hasSpend) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
            const SizedBox(height: 10),
          ],
          if (split.income > 0)
            _row(
              context,
              'Came in',
              money(split.income),
              valueColor: calm.positive,
            ),
          if (split.invested > 0)
            _row(
              context,
              'Invested',
              money(split.invested),
              note: 'not spending',
              valueColor: calm.positive,
            ),
          if (split.moved > 0)
            _row(
              context,
              'Moved',
              money(split.moved),
              note: 'card bills, top-ups',
            ),
        ],
      ],
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    String? note,
    Color? swatch,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (swatch != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 16),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          if (note != null) ...[
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
