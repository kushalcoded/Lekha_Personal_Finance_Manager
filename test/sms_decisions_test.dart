import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/providers/sms/sms_providers.dart';

void main() {
  test('reads the decisions the notification buttons wrote', () {
    expect(smsDecisions('{"a1":"add","b2":"ignore"}'), {
      'a1': 'add',
      'b2': 'ignore',
    });
  });

  test('anything unrecognised means no decision, never an auto-add', () {
    // A blob written by an older build, a truncated file, or a value we don't
    // know must leave the SMS in the review list rather than booking an
    // expense the user never approved.
    expect(smsDecisions('not json'), isEmpty);
    expect(smsDecisions('[]'), isEmpty);
    expect(smsDecisions('{}'), isEmpty);
    expect(smsDecisions('{"a1":"maybe","b2":null,"c3":7}'), isEmpty);
  });

  test('keeps the valid entries alongside invalid ones', () {
    expect(smsDecisions('{"a1":"add","b2":"maybe"}'), {'a1': 'add'});
  });
}
