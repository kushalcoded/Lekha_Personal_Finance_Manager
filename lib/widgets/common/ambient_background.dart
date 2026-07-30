import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The app's global backdrop: a flat neutral near-black. Sits behind every
/// (transparent) Scaffold. Deliberately plain — the Midnight Terminal spec
/// bans decorative glows; solid cards carry all the hierarchy.
class AmbientBackground extends StatelessWidget {
  final Widget child;

  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppTheme.ground, child: child);
  }
}
