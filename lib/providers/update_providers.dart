import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Sideloaded Android apps can't auto-update, so we check the latest GitHub
/// release ourselves and surface an "Update available" row in Settings.
const kReleasesLatestApi =
    'https://api.github.com/repos/kushalcoded/Lekha_Personal_Finance_Manager/releases/latest';
const kReleasesLatestUrl =
    'https://github.com/kushalcoded/Lekha_Personal_Finance_Manager/releases/latest';

/// Installed app version, e.g. "1.0.1".
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// A release newer than what's installed, and where to get it.
class AppRelease {
  final String version;

  /// Direct link to the APK asset, or null when the release has none attached —
  /// then the UI falls back to opening the release page in a browser.
  final String? apkUrl;

  const AppRelease({required this.version, this.apkUrl});
}

/// The newer release, or null when up to date or on web (which updates itself
/// on reload).
///
/// Throws when the check itself fails. That distinction matters: reading this
/// with `.valueOrNull` collapses a failed lookup into "up to date", so the
/// Settings row used to claim it was current while offline, having never
/// managed to look.
final updateAvailableProvider = FutureProvider<AppRelease?>((ref) async {
  if (kIsWeb) return null;
  final current = await ref.watch(appVersionProvider.future);
  final res = await http
      .get(
        Uri.parse(kReleasesLatestApi),
        headers: {'Accept': 'application/vnd.github+json'},
      )
      // Same budget the connectivity probe uses — a hung request must not leave
      // the row spinning forever.
      .timeout(const Duration(seconds: 8));
  if (res.statusCode != 200) {
    throw Exception('GitHub returned ${res.statusCode}');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final tag = body['tag_name'] as String? ?? '';
  final latest = tag.replaceFirst(RegExp('^v'), '');
  if (!isNewerVersion(latest, current)) return null;
  return AppRelease(
    version: latest,
    apkUrl: pickApkAsset(body['assets'], latest),
  );
});

/// The APK to download from a release's asset list.
///
/// Prefers the documented `Lekha-v<version>.apk` name, then any `.apk` at all,
/// so a release named differently still updates. Null when a release carries no
/// APK — the caller must keep the browser fallback rather than dead-end.
String? pickApkAsset(Object? assets, String version) {
  if (assets is! List) return null;

  String? nameOf(Object? asset) =>
      asset is Map ? asset['name']?.toString() : null;
  String? urlOf(Object? asset) =>
      asset is Map ? asset['browser_download_url']?.toString() : null;

  final apks = assets.where(
    (asset) => (nameOf(asset) ?? '').toLowerCase().endsWith('.apk'),
  );
  if (apks.isEmpty) return null;

  final wanted = 'lekha-v$version.apk'.toLowerCase();
  for (final asset in apks) {
    if (nameOf(asset)!.toLowerCase() == wanted) {
      final url = urlOf(asset);
      if (url != null && url.isNotEmpty) return url;
    }
  }
  final url = urlOf(apks.first);
  return (url == null || url.isEmpty) ? null : url;
}

/// Whether to interrupt the user about [release] on launch.
///
/// Once per version: dismissing records the version, so the prompt stays quiet
/// until there's a genuinely newer one.
bool shouldPromptForUpdate(AppRelease? release, String? dismissedVersion) {
  if (release == null) return false;
  return release.version != dismissedVersion;
}

/// True when [candidate] is a strictly newer dotted version than [current].
bool isNewerVersion(String candidate, String current) {
  List<int> parse(String v) =>
      v.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  final a = parse(candidate);
  final b = parse(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
