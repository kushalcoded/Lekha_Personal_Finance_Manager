import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The opening animation: the ₹ mark scales in, the budget-ring (the dashboard's
/// signature dial) sweeps around it, and the "Lekha" wordmark fades up — over
/// the app's ambient violet ground. Calls [onDone] when finished so the shell
/// can cross-fade in.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;

  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _markFade;
  late final Animation<double> _markScale;
  late final Animation<double> _ring;
  late final Animation<double> _wordFade;
  late final Animation<double> _wordSlide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _markFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );
    _markScale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );
    _ring = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.15, 0.75, curve: Curves.easeInOut),
    );
    _wordFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.55, 0.85, curve: Curves.easeOut),
    );
    _wordSlide = Tween(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.55, 0.9, curve: Curves.easeOut),
      ),
    );
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 128,
                  height: 128,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(128, 128),
                        painter: _DialPainter(
                          progress: _ring.value,
                          color: cs.primary,
                        ),
                      ),
                      Opacity(
                        opacity: _markFade.value,
                        child: Transform.scale(
                          scale: _markScale.value,
                          child: const Text(
                            '₹',
                            style: TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontSize: 54,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Opacity(
                  opacity: _wordFade.value,
                  child: Transform.translate(
                    offset: Offset(0, _wordSlide.value),
                    child: Text(
                      'Lekha',
                      style: TextStyle(
                        fontFamily: 'Space Grotesk',
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The budget dial: a faint full track with a violet arc that sweeps to ~72%
/// (matching the app icon's dial), with round caps.
class _DialPainter extends CustomPainter {
  final double progress; // 0..1 of the sweep
  final Color color;

  _DialPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;
    final sweep = progress * 2 * math.pi * 0.72;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.progress != progress || old.color != color;
}
