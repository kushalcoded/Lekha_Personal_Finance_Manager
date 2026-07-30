import 'package:flutter/material.dart';

import '../../../widgets/common/glass.dart';

class ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final bool isEmpty;
  final Widget? emptyState;

  const ChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.isEmpty = false,
    this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    // The section wrapper (AnalyticsSection) already provides the heading, so
    // the card itself is just the frosted chart surface — no repeated title.
    return GlassCard(
      radius: 12,
      padding: const EdgeInsets.all(16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isEmpty ? (emptyState ?? const SizedBox()) : child,
      ),
    );
  }
}
