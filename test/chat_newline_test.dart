import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/screens/ai_chat_screen.dart';

/// Shift+Enter in the assistant composer inserts a newline at the caret; the
/// caret must land after it, not before, or typing continues on the old line.
void main() {
  test('newline lands at the caret and the caret moves past it', () {
    final value = withNewline(
      const TextEditingValue(
        text: 'hello world',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );

    expect(value.text, 'hello\n world');
    expect(value.selection.baseOffset, 6);
  });

  test('newline replaces the selected range', () {
    final value = withNewline(
      const TextEditingValue(
        text: 'hello world',
        selection: TextSelection(baseOffset: 5, extentOffset: 11),
      ),
    );

    expect(value.text, 'hello\n');
    expect(value.selection.baseOffset, 6);
  });

  test('no caret yet: appends instead of throwing', () {
    final value = withNewline(const TextEditingValue(text: 'hello'));

    expect(value.text, 'hello\n');
    expect(value.selection.baseOffset, 6);
  });
}
