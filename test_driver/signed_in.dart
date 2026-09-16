import 'app.dart' show collectErrorsForDriver;
import 'clone.dart' as clone;

/// Device side of the signed-in pass: the phone's cloned data (clone.dart)
/// under the driver. The steps live in signed_in_test.dart; run it through
/// `bash test_driver/run_android.sh <backup.json>`.
Future<void> main() async {
  collectErrorsForDriver();
  await clone.main();
}
