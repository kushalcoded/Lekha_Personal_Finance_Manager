// Boots the real app on a device and walks what a fresh install sees:
// onboarding, then the login screen. A layout overflow at the device's real
// screen size fails the run on its own.
//
// Emulator only. The run uninstalls the app when it ends, and on the phone that
// wipes Lekha's local data:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_test.dart -d emulator-5554
//
// Screenshots land in build/integration_screenshots/.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:personal_expanse_tracker/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Not pumpAndSettle: loaders spin forever. Waits for [finder], then lets the
  /// transition that revealed it finish so taps and screenshots land cleanly.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('fresh install: onboarding to login', (tester) async {
    final testErrorHandler = FlutterError.onError;
    app.main();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
    }

    await waitFor(tester, find.text('Welcome to Lekha'));
    await binding.takeScreenshot('01_onboarding_welcome');

    await tester.tap(find.text('Next'));
    await waitFor(tester, find.text('Set Your Budget Targets'));
    await tester.tap(find.text('Next'));
    await waitFor(tester, find.text('Get Started'));
    await binding.takeScreenshot('02_onboarding_last');

    await tester.tap(find.text('Get Started'));
    await waitFor(tester, find.text('Continue with Google'));
    await binding.takeScreenshot('03_login');

    final createAccount = find.text('New here? Create an account');
    await tester.ensureVisible(createAccount);
    await tester.tap(createAccount);
    await waitFor(tester, find.text('Create an account with email'));
    await binding.takeScreenshot('04_create_account');

    // main() installs ErrorReporter in front of the test's handler (it still
    // forwards to it); hand the original back or the binding fails the test.
    FlutterError.onError = testErrorHandler;
  });
}
