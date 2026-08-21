import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/providers/sms/sms_providers.dart';

/// The local read that lets a detected card appear without a network round
/// trip. Null means "not sure" and costs only a fallback to the model, so every
/// ambiguous case here should return null rather than guess — being wrong is
/// worse than being slow.
void main() {
  group('reads a normal debit', () {
    test('the standard template', () {
      expect(
        quickParseSms('Rs.450.00 debited from A/c XX1234 on 12-08-26'),
        450.00,
      );
    });

    test('thousands separators', () {
      expect(quickParseSms('INR 12,499.50 spent on your card'), 12499.50);
    });

    test('the rupee sign, and no decimals', () {
      expect(quickParseSms('₹250 paid to SWIGGY via UPI'), 250);
    });

    test('case does not matter', () {
      expect(quickParseSms('RS 99 DEBITED'), 99);
      expect(quickParseSms('rs.99 debited'), 99);
    });

    test('sent — the wording this user\'s bank actually uses', () {
      expect(quickParseSms('Rs.1090 sent to Kushal via UPI Ref 123'), 1090);
    });
  });

  group('never mistakes the balance for the spend', () {
    test('takes the transaction amount, not the trailing balance', () {
      // The single most likely way to book a wrong number.
      expect(
        quickParseSms(
          'Rs.450.00 debited from A/c XX1234. Avl Bal Rs.23,891.20',
        ),
        450.00,
      );
    });

    test('bails when a balance word leads the only amount', () {
      // Nothing here says what was spent, so the model has to decide.
      expect(quickParseSms('Avl Bal Rs.23,891.20 after debit'), isNull);
      expect(
        quickParseSms('Your available balance is Rs.5000 (debited)'),
        isNull,
      );
    });
  });

  group('refuses anything that is not a spend', () {
    test('credits and refunds', () {
      expect(quickParseSms('Rs.500 credited to your A/c'), isNull);
      expect(quickParseSms('Refund of Rs.300 processed to your card'), isNull);
      expect(quickParseSms('Rs.120 reversed to your account'), isNull);
    });

    test('an OTP that happens to mention money', () {
      expect(
        quickParseSms('OTP 445566 for a payment of Rs.2000. Do not share.'),
        isNull,
      );
      expect(
        quickParseSms('Use one time password 1234 to authorise Rs.99 paid'),
        isNull,
      );
    });

    test('a message with money but no debit word', () {
      expect(quickParseSms('Your statement of Rs.5000 is ready'), isNull);
    });

    test('a debit word but no amount the app can read', () {
      expect(quickParseSms('Your card was debited today'), isNull);
      expect(quickParseSms('450 debited'), isNull); // no currency marker
    });

    test('empty and junk', () {
      expect(quickParseSms(''), isNull);
      expect(quickParseSms('   '), isNull);
      expect(quickParseSms('Rs.0 debited'), isNull);
    });
  });
}
