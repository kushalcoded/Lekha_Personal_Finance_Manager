import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/providers/payment/payment_method_providers.dart';

/// The shipped list now names the instrument rather than the app. A stored
/// list is never replaced — deletions and additions are the user's — but two
/// labels were renamed, and leaving the old name behind would split one
/// payment method into two buckets in the breakdown.
void main() {
  test('the two renamed labels are carried across, in place', () {
    expect(
      upgradePaymentMethods([
        'Cash',
        'GPay',
        'PhonePe',
        'Paytm',
        'Bank Transfer',
        'Card',
      ]),
      ['Cash', 'GPay', 'PhonePe', 'Paytm', 'Net Banking', 'Credit Card'],
    );
  });

  test('order is left alone — the list is the user\'s to sort', () {
    expect(upgradePaymentMethods(['Card', 'Cash']), ['Credit Card', 'Cash']);
  });

  test('a method the user deleted stays deleted', () {
    expect(upgradePaymentMethods(['Cash', 'Card']), ['Cash', 'Credit Card']);
  });

  test('a name they already use is not created twice', () {
    // Someone who added "Credit Card" by hand and kept the old "Card" keeps
    // both rather than ending up with two identical entries.
    expect(upgradePaymentMethods(['Credit Card', 'Card']), [
      'Credit Card',
      'Card',
    ]);
  });

  test('a list with nothing to rename comes back unchanged', () {
    const list = ['UPI', 'Cash', 'Debit Card'];
    expect(upgradePaymentMethods(list), list);
  });

  test('custom methods are untouched', () {
    expect(upgradePaymentMethods(['Sodexo', 'Card']), [
      'Sodexo',
      'Credit Card',
    ]);
  });
}
