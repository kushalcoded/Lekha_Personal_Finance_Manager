import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:personal_expanse_tracker/main.dart';
import 'package:personal_expanse_tracker/providers/auth/auth_provider.dart';
import 'package:personal_expanse_tracker/services/backup/backup_file_service.dart';
import 'package:personal_expanse_tracker/services/storage/hive_service.dart';
import 'package:personal_expanse_tracker/services/supabase/supabase_service.dart';

/// The phone's data on the emulator, cut off from the cloud. Installed and fed
/// by test_driver/clone_to_emulator.sh.
///
/// The backup's own user id is treated as signed in, because data only shows
/// for its owner. Supabase runs with no session, so nothing here can touch the
/// real account: every table is `to authenticated` + `auth.uid() = user_id`,
/// shares skip without `currentUser`, and AI needs a JWT. Sync still tries and
/// is refused, the same as for anyone holding the public key.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await HiveService.initialize();
  // Code all over assumes a client exists; without one it throws, not skips.
  await SupabaseService.initialize();
  final hive = HiveService();

  final docs = await getApplicationDocumentsDirectory();
  final incoming = File('${docs.path}/clone.json');
  if (incoming.existsSync()) {
    final snapshot = await const BackupFileService().readBackupPayload(
      incoming.path,
    );
    await hive.restoreFromBackup(snapshot);
    await hive.setOnboardingCompleted(true);
    await hive.setLocalDataOwner(snapshot['userId'] as String);
    // Hive holds it now; don't leave a second copy of someone's finances.
    incoming.deleteSync();
  }

  final userId = hive.getLocalDataOwner();
  if (userId.isEmpty) {
    throw StateError('No clone yet: run test_driver/clone_to_emulator.sh');
  }
  runApp(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => _ClonedAccount(userId)),
      ],
      child: const MyApp(),
    ),
  );
}

/// Not a subclass: AuthNotifier listens to Supabase, which would report "no
/// session" and send the app to the login screen. Sign-in, sign-out and the
/// rest are no-ops here.
class _ClonedAccount extends StateNotifier<AuthState> implements AuthNotifier {
  _ClonedAccount(String userId)
    : super(AuthState(isAuthenticated: true, userId: userId, resolved: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<bool>.value(false);
}
