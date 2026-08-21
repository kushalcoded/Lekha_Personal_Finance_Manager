import 'package:flutter/material.dart';

/// A page-level scope switch: one rounded track split into segments, the active
/// one filled with the accent.
///
/// Deliberately not a [ChoicePill]: those sit inside forms as filters, and this
/// governs everything below it. Reusing them made the control read as one more
/// field rather than the thing that decides what the whole screen means.
///
/// Below [compactWidth] the track goes full width and switches to short labels,
/// which is the only way three segments fit on a 320dp phone without wrapping.
class SegmentedScope<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T value) label;
  final String Function(T value) shortLabel;
  final double compactWidth;

  const SegmentedScope({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.label,
    required this.shortLabel,
    this.compactWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < compactWidth;

    final track = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: values.map((value) {
          final segment = _Segment(
            text: compact ? shortLabel(value) : label(value),
            selected: value == selected,
            onTap: () => onChanged(value),
          );
          return compact ? Expanded(child: segment) : segment;
        }).toList(),
      ),
    );

    // Left-aligned on desktop rather than stretched: a 1400px-wide switch for
    // three words reads as a banner, not a control.
    return compact
        ? track
        : Align(alignment: Alignment.centerLeft, child: track);
  }
}

class _Segment extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                // Dark text on the accent fill — white on violet fails contrast.
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
