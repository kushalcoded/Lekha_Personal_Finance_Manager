import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Label every how-many-th point along a chart's bottom axis so no two labels
/// touch.
///
/// Every point used to get one. A cycle is up to 31 days of "Sep 14", and even
/// twelve "Aug"s crowd a phone — and the chart library nudges the first and last
/// label inward to keep them on the card, straight into their neighbours. This
/// measures the widest label at the real text size and leaves room for that
/// nudge.
int axisLabelStep({
  required double width,
  required List<String> labels,
  required TextStyle? style,
  required TextScaler textScaler,
  bool bars = false,
}) {
  final count = labels.length;
  if (count <= 1 || width <= 0) return 1;
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    widest = math.max(widest, painter.width);
  }
  // Points on a line sit edge to edge; bars sit in the middle of equal slots.
  final spacing = bars ? width / count : width / (count - 1);
  // A label's own width, plus up to half of one for the edge nudge, plus a gap.
  final needed = widest * 1.8 + 6;
  return math.max(1, (needed / spacing).ceil());
}

/// Whether point [index] of [count] gets its label. Counted back from the last
/// point, so the most recent one — the one people look for — is always labelled.
bool axisLabelShown(int index, int count, int step) =>
    (count - 1 - index) % step == 0;
