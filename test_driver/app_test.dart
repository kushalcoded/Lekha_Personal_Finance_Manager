import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

/// Host side of `flutter drive --target=test_driver/app.dart`: walks what a
/// fresh install sees, onboarding to the login screen, and screenshots each
/// stop into build/integration_screenshots/.
Future<void> main() async {
  final driver = await FlutterDriver.connect();
  const timeout = Duration(seconds: 20);
  // main() opens Hive and Supabase before runApp; finders fail until then.
  await driver.waitUntilFirstFrameRasterized();

  Future<void> shoot(String name) async {
    final file = File('build/integration_screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(await driver.screenshot());
  }

  try {
    await driver.waitFor(find.text('Welcome to Lekha'), timeout: timeout);
    await shoot('01_onboarding_welcome');

    await driver.tap(find.text('Next'));
    await driver.waitFor(
      find.text('Set Your Budget Targets'),
      timeout: timeout,
    );
    await driver.tap(find.text('Next'));
    await driver.waitFor(find.text('Get Started'), timeout: timeout);
    await shoot('02_onboarding_last');

    await driver.tap(find.text('Get Started'));
    await driver.waitFor(find.text('Continue with Google'), timeout: timeout);
    await shoot('03_login');

    final createAccount = find.text('New here? Create an account');
    await driver.scrollIntoView(createAccount);
    await driver.tap(createAccount);
    await driver.waitFor(
      find.text('Create an account with email'),
      timeout: timeout,
    );
    await shoot('04_create_account');

    final errors = await driver.requestData('errors');
    if (errors.isNotEmpty) {
      throw StateError('The app reported errors:\n$errors');
    }
    stdout.writeln('PASS: onboarding to login, 4 screenshots');
  } finally {
    await driver.close();
  }
}
