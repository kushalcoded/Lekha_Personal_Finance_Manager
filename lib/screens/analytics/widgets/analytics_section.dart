import 'package:flutter/material.dart';

class AnalyticsSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const AnalyticsSection({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
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

    // When given a bounded height (desktop two-up rows equalized via
    // IntrinsicHeight), let the card stretch so paired sections line up.
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedHeight;
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
            if (bounded) Expanded(child: child) else child,
          ],
        );
      },
    );
  }
}
