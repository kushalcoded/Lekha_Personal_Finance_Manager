import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

/// Host side of `flutter drive --target=test_driver/signed_in.dart`: every tab
/// and the add sheet on the phone's cloned data, screenshotted into
/// build/integration_screenshots/ after the onboarding shots.
Future<void> main() async {
  final driver = await FlutterDriver.connect();
  const timeout = Duration(seconds: 30);
  await driver.waitUntilFirstFrameRasterized();

  Future<void> shoot(String name) async {
    final file = File('build/integration_screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(await driver.screenshot());
  }

  const tabs = {
    'Home': 'DashboardScreen',
    'Expenses': 'ExpensesScreen',
    'Insights': 'AnalyticsScreen',
    'Debts': 'DebtsScreen',
  };

  try {
    // Unsynchronized: live screens never go frame-idle, so frame sync would
    // wait on them forever. screenshot() itself waits for the paint.
    await driver.runUnsynchronized(() async {
      await driver.waitFor(find.byType('FloatingGlassNav'), timeout: timeout);
      var shot = 5;
      for (final MapEntry(key: label, value: screen) in tabs.entries) {
        await driver.tap(
          find.descendant(
            of: find.byType('FloatingGlassNav'),
            matching: find.text(label),
            firstMatchOnly: true,
          ),
        );
        await driver.waitFor(find.byType(screen), timeout: timeout);
        await shoot('0${shot++}_${label.toLowerCase()}');
      }

      await driver.tap(find.byType('_AddButton'));
      await driver.waitFor(find.byType('AddExpenseForm'), timeout: timeout);
      await shoot('09_add_expense');

      final errors = await driver.requestData('errors');
      if (errors.isNotEmpty) {
        throw StateError('The app reported errors:\n$errors');
      }
    });
    stdout.writeln('PASS: signed-in tabs and add sheet, 5 screenshots');
  } finally {
    await driver.close();
  }
}
