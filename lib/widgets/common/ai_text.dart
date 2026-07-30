import 'package:flutter/material.dart';

/// Renders model output as clean text: `**bold**`/`__bold__` become real bold,
/// `*italic*`/`_italic_` become italic, inline `code` is de-fenced, and stray
/// markdown noise (leading `#`, `- `/`* ` bullets, leftover `*`/`` ` ``) is
/// stripped — so the UI never shows raw asterisks even if the model ignores the
/// "plain text" instruction.
class AiText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const AiText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(TextSpan(children: _spans(_clean(text))), style: base);
  }

  /// Line-level cleanup: drop heading markers, normalise bullets to "• ".
  static String _clean(String raw) {
    final lines = raw.trim().split('\n').map((line) {
      var s = line.trimRight();
      s = s.replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '');
      s = s.replaceFirst(RegExp(r'^\s*[-*•]\s+'), '• ');
      return s;
    });
    return lines.join('\n');
  }

  static final _md = RegExp(
    r'\*\*(.+?)\*\*|__(.+?)__|\*(.+?)\*|_(.+?)_|`(.+?)`',
    dotAll: true,
  );

  static List<InlineSpan> _spans(String text) {
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _md.allMatches(text)) {
      if (m.start > i) {
        spans.add(TextSpan(text: _plain(text.substring(i, m.start))));
      }
      final bold = m.group(1) ?? m.group(2);
      final italic = m.group(3) ?? m.group(4);
      final code = m.group(5);
      if (bold != null) {
        spans.add(
          TextSpan(
            text: bold,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (italic != null) {
        spans.add(
          TextSpan(
            text: italic,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        spans.add(TextSpan(text: code));
      }
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: _plain(text.substring(i))));
    return spans;
  }

  /// Remove any leftover unmatched markdown characters from a plain run.
  static String _plain(String s) => s.replaceAll(RegExp(r'[`*_]{1,}'), '');
}
