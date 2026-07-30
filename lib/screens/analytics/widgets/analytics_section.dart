import 'package:flutter/material.dart';

class AnalyticsSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  /// Set true only inside a bounded-height row (desktop IntrinsicHeight
  /// pairs) so the card stretches to match its partner. Must stay a plain
  /// flag — a LayoutBuilder here reports zero intrinsic height in release
  /// builds and collapses the whole row.
  final bool stretch;

  const AnalyticsSection({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.stretch = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitleWidgets = subtitle == null
        ? null
        : [
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ];
    final trailingWidgets = trailing == null ? null : [trailing!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...?trailingWidgets,
          ],
        ),
        ...?subtitleWidgets,
        const SizedBox(height: 12),
        if (stretch) Expanded(child: child) else child,
      ],
    );
  }
}
