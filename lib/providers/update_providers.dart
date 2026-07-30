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

/// The newer release's version string, or null when up to date, offline, or
/// on web (which updates itself on reload).
final updateAvailableProvider = FutureProvider<String?>((ref) async {
  if (kIsWeb) return null;
  final current = await ref.watch(appVersionProvider.future);
  final res = await http.get(
    Uri.parse(kReleasesLatestApi),
    headers: {'Accept': 'application/vnd.github+json'},
  );
  if (res.statusCode != 200) return null;
  final tag =
      (jsonDecode(res.body) as Map<String, dynamic>)['tag_name'] as String? ??
      '';
  final latest = tag.replaceFirst(RegExp('^v'), '');
  return isNewerVersion(latest, current) ? latest : null;
});

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
