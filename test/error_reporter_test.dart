import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expanse_tracker/services/errors/error_reporter.dart';

/// A crash loop can throw the same error many times a second, and the switch
/// has to actually stop reports — both are the difference between a useful
/// table and an unreadable one.
void main() {
  setUp(ErrorReporter.resetForTest);

  test('the same error is filed once per run', () {
    expect(
      ErrorReporter.shouldReport('Null check operator used on a null'),
      isTrue,
    );
    expect(
      ErrorReporter.shouldReport('Null check operator used on a null'),
      isFalse,
    );
    expect(
      ErrorReporter.shouldReport('RangeError: index out of range'),
      isTrue,
    );
  });

  test('switching it off stops everything, including new errors', () {
    ErrorReporter.enabled = false;
    expect(ErrorReporter.shouldReport('something new'), isFalse);

    ErrorReporter.enabled = true;
    expect(ErrorReporter.shouldReport('something new'), isTrue);
  });
}
