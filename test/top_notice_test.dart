import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/main.dart' show navigatorKey;
import 'package:personal_expanse_tracker/widgets/common/top_notice.dart';

/// Messages used to be SnackBars, which sat at the bottom of the screen right
/// over the + button.
void main() {
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: SizedBox.expand()),
    ),
  );

  testWidgets('shows at the top, clear of the + button', (tester) async {
    await pumpApp(tester);
    showNotice('Expense saved');
    await tester.pumpAndSettle();

    final box = tester.getRect(find.text('Expense saved'));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(box.top, lessThan(screen.height / 4));

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Expense saved'), findsNothing);
  });

  testWidgets('two messages in the same frame do not strand the first', (
    tester,
  ) async {
    // What saving a detected payment does: the caller's onSaved posts one
    // notice and the sheet posts another straight after, before any frame
    // has built the first. The first was skipped by a "mounted" check, then
    // built a frame later with nothing left that would ever remove it — and
    // stayed on screen across every tab.
    await pumpApp(tester);
    showNotice('✓ Added — synced to all devices');
    showNotice('Expense saved');
    await tester.pumpAndSettle();
    expect(find.text('✓ Added — synced to all devices'), findsNothing);
    expect(find.text('Expense saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Expense saved'), findsNothing);
    expect(find.text('✓ Added — synced to all devices'), findsNothing);
  });

  testWidgets('a new message replaces the old one', (tester) async {
    await pumpApp(tester);
    showNotice('First');
    await tester.pump(const Duration(milliseconds: 100));
    showNotice('Second');
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    // The first one's timer must not take the second down early.
    await tester.pump(const Duration(milliseconds: 2950));
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('Undo runs and closes the notice', (tester) async {
    await pumpApp(tester);
    var undone = false;
    showNotice(
      'Expense deleted',
      actionLabel: 'Undo',
      onAction: () {
        undone = true;
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
    expect(find.text('Expense deleted'), findsNothing);
  });
}
