import 'dart:ui';

import 'package:flutter/material.dart';

/// A frosted-glass surface: blurs whatever is behind it, tinted and bordered.
/// The app runs over an [AmbientBackground], so there is always something to
/// blur. Performance is a non-goal here (flagship target) — depth is the point.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? tint;
  final double tintOpacity;
  final Border? border;
  final Gradient? gradient;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.blur = 12,
    this.tint,
    this.tintOpacity = 0.42,
    this.border,
    this.gradient,
    this.shadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    final fill = (tint ?? const Color(0xFF1E1B28)).withValues(alpha: tintOpacity);
    final accent = Theme.of(context).colorScheme.primary;

    // A faint violet sheen from the top-right — the same direction as the
    // ambient glow — so the surface reads as glass on-brand and every card is
    // lit consistently, even over a flat dark background where blur shows little.
    final surfaceGradient =
        gradient ??
        LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            accent.withValues(alpha: 0.16),
            fill,
            fill,
          ],
          stops: const [0.0, 0.4, 1.0],
        );

    Widget content = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: surfaceGradient,
            borderRadius: br,
            border:
                border ??
                Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
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
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                spreadRadius: -14,
                offset: const Offset(0, 12),
              ),
            ],
      ),
      child: content,
    );
  }
}
