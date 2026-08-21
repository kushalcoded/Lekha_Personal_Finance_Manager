import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('lekha/update');

/// Downloads a release APK and hands it to Android's package installer, so an
/// update never has to detour through a browser and the Downloads folder.
///
/// The app is signed with the same key every build, so this installs in place
/// over the running app and keeps its data.
class UpdateInstaller {
  /// Fetch the APK, reporting 0..1 progress. Returns the file path.
  ///
  /// Streamed rather than buffered so progress is real and a large APK never
  /// sits entirely in memory.
  Future<String> download(
    String url,
    String version, {
    void Function(double progress)? onProgress,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await httpClient.send(request);
      if (response.statusCode != 200) {
        throw Exception('Download failed (${response.statusCode})');
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}Lekha-v$version.apk',
      );
      final sink = file.openWrite();
      final total = response.contentLength ?? 0;
      var received = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }

      final bytes = await file.length();
      if (bytes == 0) throw Exception('Downloaded file was empty');

      // A redirect to a login page, a captive portal, or a 404 body would
      // otherwise be handed to the package installer as though it were an app.
      final head = await file.openRead(0, 2).first;
      if (!looksLikeApk(head)) {
        await file.delete();
        throw Exception('That download was not an APK');
      }
      return file.path;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// True when [head] starts with the zip magic number. An APK is a zip.
  static bool looksLikeApk(List<int> head) =>
      head.length >= 2 && head[0] == 0x50 && head[1] == 0x4B;

  /// Whether Android will let Lekha install packages. False until the user
  /// grants "install unknown apps" for this app specifically — without it the
  /// install intent does nothing at all, silently.
  Future<bool> canInstall() async {
    try {
      return (await _channel.invokeMethod<bool>('canInstall')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Send the user to the system screen that grants the above.
  Future<void> requestInstallPermission() async {
    try {
      await _channel.invokeMethod<void>('requestInstallPermission');
    } catch (_) {
      // Non-Android, or the settings screen is unavailable: the caller still
      // has the browser fallback.
    }
  }

  /// Hand the APK to Android's installer.
  Future<void> install(String path) =>
      _channel.invokeMethod<void>('installApk', path);
}

/// Top-level alias so tests can reach the check without a plugin binding.
bool looksLikeApk(List<int> head) => UpdateInstaller.looksLikeApk(head);
