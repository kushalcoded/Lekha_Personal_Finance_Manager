import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../supabase/supabase_service.dart';

/// Crashes, filed to `app_errors` (see supabase/app_errors.sql).
///
/// Now that other people run this app, "it didn't work" is all a bug report
/// can say without one. Everything here fails open and silently: a reporter
/// that throws, blocks or retries would be worse than the fault it describes.
class ErrorReporter {
  /// Mirrors the Settings switch. Set before the first frame from the stored
  /// setting, and again whenever it is toggled.
  static bool enabled = true;

  static String _version = '';
  static final Set<String> _seen = <String>{};

  /// One row per distinct message per run — a build loop can throw the same
  /// error sixty times a second, and none of those repeats say anything new.
  @visibleForTesting
  static bool shouldReport(String message) => enabled && _seen.add(message);

  @visibleForTesting
  static void resetForTest() {
    enabled = true;
    _seen.clear();
  }

  /// Routes Flutter's two error channels here without replacing the console
  /// output, which is what you actually read while developing.
  static Future<void> install() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Version is a nicety; a report without one still beats no report.
    }

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return false; // Not handled — let the platform log it as it would.
    };
  }

  static void report(Object error, StackTrace? stack) {
    if (kDebugMode) return; // Dev noise; the console already has it.
    final message = error.toString();
    if (!shouldReport(message)) return;
    unawaited(_send(message, stack));
  }

  static Future<void> _send(String message, StackTrace? stack) async {
    try {
      final client = SupabaseService.client;
      await client.from('app_errors').insert({
        'user_id': client.auth.currentUser?.id,
        'version': _version,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'message': message.length > 500 ? message.substring(0, 500) : message,
        // A full stack can run to tens of kilobytes; the top of it is the part
        // that ever gets read.
        'stack': stack?.toString().split('\n').take(30).join('\n'),
      });
    } catch (_) {
      // Offline, signed out, table missing, RLS — never worth surfacing.
    }
  }
}
