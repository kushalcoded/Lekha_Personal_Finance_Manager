import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host side of `flutter drive`: writes each takeScreenshot() to disk.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/integration_screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
