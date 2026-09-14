import 'dart:convert';

/// How a point on the Home summary should read at a glance.
enum InsightTone { alert, warn, good, info }

/// Where tapping a point takes you.
enum InsightTarget { debts, expenses, insights }

/// One line of the Home AI summary.
class DashboardInsight {
  final InsightTone tone;

  /// Short, with amounts wrapped in `**` so they render bold.
  final String text;
  final InsightTarget? target;

  const DashboardInsight({required this.tone, required this.text, this.target});
}

class DashboardSummary {
  final List<DashboardInsight> items;
  final DateTime generatedAt;

  const DashboardSummary({required this.items, required this.generatedAt});
}

/// The model's reply as points. Asked for JSON so the layout never depends on
/// how it phrased things; if it answers in lines anyway, each line becomes a
/// neutral point rather than the card showing nothing.
List<DashboardInsight> parseDashboardInsights(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start != -1 && end > start) {
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      final items = decoded is Map ? decoded['items'] : null;
      if (items is List) {
        final out = [
          for (final item in items.whereType<Map>())
            if ('${item['text'] ?? ''}'.trim().isNotEmpty)
              DashboardInsight(
                tone:
                    InsightTone.values
                        .where((t) => t.name == item['tone'])
                        .firstOrNull ??
                    InsightTone.info,
                text: '${item['text']}'.trim(),
                target: InsightTarget.values
                    .where((t) => t.name == item['target'])
                    .firstOrNull,
              ),
        ];
        if (out.isNotEmpty) return out.take(3).toList();
      }
    } on FormatException {
      // Fall through to reading it as lines.
    }
  }
  return [
    for (final line in raw.split('\n'))
      if (line.replaceFirst(RegExp(r'^\s*([-*•·]|\d+[.)])\s*'), '').trim()
          case final text when text.isNotEmpty && !text.startsWith('{'))
        DashboardInsight(tone: InsightTone.info, text: text),
  ].take(3).toList();
}
