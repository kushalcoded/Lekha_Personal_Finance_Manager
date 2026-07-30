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
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 12,
    this.border,
    this.gradient,
    this.shadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? const Color(0xFF131318) : null,
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
