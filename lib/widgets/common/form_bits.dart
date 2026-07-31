import 'package:flutter/material.dart';

/// Small uppercase data label — JetBrains Mono, the Midnight Terminal
/// signature detail. Used above fields and sections.
class FieldLabel extends StatelessWidget {
  final String text;

  const FieldLabel(this.text, {super.key});

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
          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
