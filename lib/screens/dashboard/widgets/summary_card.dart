import 'package:flutter/material.dart';

class SummaryCard extends StatefulWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  @override
  State<SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<SummaryCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 240;
        final isTightHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight < 96;
        final horizontalPadding = isCompact ? 12.0 : 14.0;
        final verticalPadding = isTightHeight ? 6.0 : horizontalPadding;
        final iconSize = isTightHeight
            ? (isCompact ? 16.0 : 20.0)
            : (isCompact ? 18.0 : 22.0);
        final iconPadding = isTightHeight ? 4.0 : 8.0;
        final topGap = isTightHeight ? 3.0 : 8.0;
        final valueGap = isTightHeight ? 2.0 : 6.0;
        final textHeight = isTightHeight ? 1.0 : 1.1;
        final titleStyle = theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          height: textHeight,
        );
        final valueStyle =
            (isTightHeight
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleLarge)
                ?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: textHeight,
                );
        final subtitleStyle =
            (isTightHeight
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.bodySmall)
                ?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: textHeight,
                );

        final contentWidth = (constraints.maxWidth - (horizontalPadding * 2))
            .clamp(0.0, double.infinity)
            .toDouble();

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 88),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  widget.accentColor.withValues(alpha: 0.12),
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: _isHovered
                    ? widget.accentColor.withValues(alpha: 0.3)
                    : colorScheme.outline.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _isHovered ? 0.12 : 0.08,
                  ),
                  blurRadius: _isHovered ? 22 : 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.all(iconPadding),
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            widget.icon,
                            size: iconSize,
                            color: widget.accentColor,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: topGap),
                    Text(
                      widget.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
                    SizedBox(height: valueGap),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
