import 'package:flutter_test/flutter_test.dart';

import 'package:personal_expanse_tracker/utils/amount_expression.dart';

void main() {
  test('plain numbers still parse', () {
    expect(parseAmountExpression('480'), 480);
    expect(parseAmountExpression('45.50'), 45.5);
    expect(parseAmountExpression(' 480 '), 480);
    expect(parseAmountExpression('₹480'), 480);
  });

  test('plus, space, and comma all sum', () {
    expect(parseAmountExpression('450+89'), 539);
    expect(parseAmountExpression('450 89'), 539);
    expect(parseAmountExpression('450, 89'), 539);
    expect(parseAmountExpression('450+89+11'), 550);
    expect(parseAmountExpression('10.5 4.5'), 15);
  });

  test('minus subtracts', () {
    expect(parseAmountExpression('500-60'), 440);
    expect(parseAmountExpression('500-60+10'), 450);
  });

  test('mid-typing separators do not kill the parse', () {
    expect(parseAmountExpression('450+'), 450);
    expect(parseAmountExpression('450,'), 450);
    expect(parseAmountExpression('450 '), 450);
  });

  test('garbage is rejected', () {
    expect(parseAmountExpression(''), isNull);
    expect(parseAmountExpression('abc'), isNull);
    expect(parseAmountExpression('45a'), isNull);
    expect(parseAmountExpression('+'), isNull);
    expect(parseAmountExpression('4..5'), isNull);
  });

  test('multi-term detection drives the live hint', () {
    expect(isMultiTermAmount('450+89'), isTrue);
    expect(isMultiTermAmount('450, 89'), isTrue);
    expect(isMultiTermAmount('480'), isFalse);
    expect(isMultiTermAmount('abc'), isFalse);
  });
}
