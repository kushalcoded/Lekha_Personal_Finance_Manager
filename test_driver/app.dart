import 'package:flutter/foundation.dart';
import 'package:flutter_driver/driver_extension.dart';

import 'package:personal_expanse_tracker/main.dart' as app;

/// Device side of the end-to-end run; the steps live in app_test.dart.
///
/// flutter_driver rather than integration_test: the latter's Android plugin
/// needs Gradle downloads this PC's TLS proxy blocks, and it broke every debug
/// build just by sitting in pubspec.yaml.
///
/// Run it with `bash test_driver/run_android.sh` (emulator only).
void main() {
  collectErrorsForDriver();
  app.main();
}

/// A layout overflow doesn't fail a driver run by itself, so framework errors
/// are collected for the host to fetch with `requestData` at the end.
void collectErrorsForDriver() {
  final errors = <String>[];
  enableFlutterDriverExtension(handler: (_) async => errors.join('\n\n'));
  final printError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
    printError?.call(details);
  };
}
