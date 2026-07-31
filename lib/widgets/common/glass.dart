import 'package:flutter/material.dart';

/// The app's standard card surface: a solid dark tile with a hairline border
/// and a soft drop shadow. (Historically frosted glass — flattened for a
/// calmer, more deliberate look; the name stayed to keep call sites stable.)
/// Accent cards pass an explicit [gradient] or [border].
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Border? border;
  final Gradient? gradient;

  /// Overrides the default solid fill — used for semantic tint washes
  /// (e.g. positive/negative banners at ~7% alpha over the ground).
  final Color? color;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 12,
    this.border,
    this.gradient,
    this.color,
    this.shadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? const Color(0xFF131318)) : null,
        gradient: gradient,
        borderRadius: br,
        border:
            border ?? Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: child,
    );

    if (onTap != null) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(borderRadius: br, onTap: onTap),
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow:
            shadow ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 18,
                spreadRadius: -12,
                offset: const Offset(0, 8),
              ),
            ],
      ),
      child: content,
    );
  }
}

/// Solid card with a 2px accent stripe down the left edge — the mockup's AI
/// card treatment. (A non-uniform Border can't carry a borderRadius, hence
/// the clipped Stack.)
class AccentEdgeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AccentEdgeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF131318),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: cs.primary),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
