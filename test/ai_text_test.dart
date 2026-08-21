import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/widgets/common/ai_text.dart';

String _rendered(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.byType(RichText));
  return (rich.text as TextSpan).toPlainText();
}

void main() {
  testWidgets('AiText strips markdown noise and keeps the words', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiText(
            '**Prioritize** debt now.\n'
            '- item one\n'
            'use `gpay` and _stay_ calm',
          ),
        ),
      ),
    );

    final text = _rendered(tester);
    // No raw markdown characters survive.
    expect(text.contains('*'), isFalse);
    expect(text.contains('`'), isFalse);
    expect(text.contains('_'), isFalse);
    // Words are preserved; a leading dash becomes a bullet.
    expect(text.contains('Prioritize debt now.'), isTrue);
    expect(text.contains('• item one'), isTrue);
    expect(text.contains('use gpay and stay calm'), isTrue);
  });

  testWidgets('AiText renders **bold** as a bold span', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiText('watch **Food** spend'))),
    );

    final root =
        tester.widget<RichText>(find.byType(RichText)).text as TextSpan;
    TextSpan? boldSpan;
    void visit(InlineSpan s) {
      if (s is TextSpan) {
        if (s.text == 'Food' && s.style?.fontWeight == FontWeight.w700) {
          boldSpan = s;
        }
        s.children?.forEach(visit);
      }
    }

    visit(root);
    expect(boldSpan, isNotNull);
  });
}
