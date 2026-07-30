import 'package:flutter_test/flutter_test.dart';

import 'package:personal_expanse_tracker/providers/update_providers.dart';

void main() {
  test('isNewerVersion compares dotted versions numerically', () {
    expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
    expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.10', '1.0.9'), isTrue); // numeric, not lexical
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    expect(isNewerVersion('1.0', '1.0.0'), isFalse); // missing parts are zero
    expect(isNewerVersion('1.0.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('', '1.0.0'), isFalse); // garbage never updates
  });
}
