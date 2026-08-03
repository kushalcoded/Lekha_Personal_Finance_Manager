import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';

/// Small uppercase data label — JetBrains Mono, the Midnight Terminal
/// signature detail. Used above fields and sections.
class FieldLabel extends StatelessWidget {
  final String text;

  /// Defaults to the muted label colour; pass the accent to mark an active
  /// state (e.g. the detected-SMS selection header).
  final Color? color;

  const FieldLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 10,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w500,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A selectable pill with an optional leading colour dot or icon.
/// [selectedColor] tints the selected state with a semantic colour (mockup:
/// category chips take the category tint instead of violet).
class ChoicePill extends StatelessWidget {
  final String label;
  final Color? dotColor;
  final IconData? icon;
  final bool selected;
  final Color? selectedColor;
  final VoidCallback onTap;

  const ChoicePill({
    super.key,
    required this.label,
    this.dotColor,
    this.icon,
    required this.selected,
    this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = selectedColor ?? cs.primary;
    final selectedText = selectedColor == null
        ? cs.primary
        : Color.lerp(selectedColor, Colors.white, 0.35)!;
    final fg = selected ? selectedText : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.15)
              : const Color(0xFF1A1A21),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 7),
            ],
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: selected ? selectedText : cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says — while the date can still be changed — that this one falls outside
/// the current salary cycle, so the expense saves but stays out of that
/// cycle's list and totals. Without it a saved expense simply vanishes and
/// reads as "it didn't save".
class OutOfCycleNote extends StatelessWidget {
  final DateTime date;
  final VoidCallback onUseToday;

  const OutOfCycleNote({
    super.key,
    required this.date,
    required this.onUseToday,
  });

  /// True when [date] falls before the cycle beginning [cycleStart].
  static bool applies(DateTime date, DateTime cycleStart) => date.isBefore(
    DateTime(cycleStart.year, cycleStart.month, cycleStart.day),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calm = CalmColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: calm.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: calm.warning.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dated ${DateFormat('d MMM').format(date)} — before this cycle '
            "started, so it stays out of this cycle's list and totals.",
            style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onUseToday,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                "Use today's date instead",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact pill action used by the detected-SMS cards (mockup: `Add` in a
/// violet-tinted pill, `Dismiss` in a plain one).
class SmsActionPill extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const SmsActionPill({
    super.key,
    required this.label,
    this.primary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: primary
              ? cs.primary.withValues(alpha: 0.14)
              : const Color(0xFF1A1A21),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: primary
                ? cs.primary.withValues(alpha: 0.30)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: primary ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Full-width violet gradient primary button (mockup `.savebtn`).
class GradientButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const GradientButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Flat accent fill with dark text (spec: no gradients, no glow; white
    // on the light violet fails contrast).
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: cs.primary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: 52,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
