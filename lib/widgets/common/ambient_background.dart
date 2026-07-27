import 'package:flutter/material.dart';

/// The app's global backdrop: a near-black ground with soft violet glows in the
/// corners. Sits behind every (transparent) Scaffold so glass surfaces have
/// something to blur and the UI never reads as flat.
class AmbientBackground extends StatelessWidget {
  final Widget child;

  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0E0D12),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            right: -90,
            child: _glow(const Color(0xFF8B7CF6), 340, 0.22),
          ),
          Positioned(
            bottom: -160,
            left: -110,
            child: _glow(const Color(0xFF6E5CE6), 360, 0.16),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size, double opacity) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
