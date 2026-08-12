import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:personal_expanse_tracker/providers/update_providers.dart';
import 'package:personal_expanse_tracker/services/update/update_installer.dart';

Map<String, Object?> asset(String name, {String? url}) => {
  'name': name,
  'browser_download_url': url ?? 'https://example.com/$name',
};

void main() {
  test('isNewerVersion compares dotted versions numerically', () {
    expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
    expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.10', '1.0.9'), isTrue); // numeric, not lexical
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
    expect(isNewerVersion('1.0', '1.0.0'), isFalse); // missing parts are zero
    expect(isNewerVersion('1.0.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('', '1.0.0'), isFalse); // garbage never updates
  });

  group('pickApkAsset', () {
    test('prefers the conventionally named APK', () {
      final url = pickApkAsset([
        asset('source.zip'),
        asset('Lekha-v1.1.3.apk', url: 'https://example.com/right.apk'),
        asset('Lekha-debug.apk'),
      ], '1.1.3');
      expect(url, 'https://example.com/right.apk');
    });

    test('falls back to any APK when the name differs', () {
      // A release named by hand should still be installable.
      final url = pickApkAsset([
        asset('notes.txt'),
        asset('app-release.apk', url: 'https://example.com/other.apk'),
      ], '1.1.3');
      expect(url, 'https://example.com/other.apk');
    });

    test('matching ignores case', () {
      final url = pickApkAsset([
        asset('LEKHA-V1.1.3.APK', url: 'https://example.com/shouty.apk'),
      ], '1.1.3');
      expect(url, 'https://example.com/shouty.apk');
    });

    test('null when the release carries no APK', () {
      // The caller must keep the browser fallback rather than dead-end.
      expect(pickApkAsset([asset('source.zip')], '1.1.3'), isNull);
      expect(pickApkAsset(const [], '1.1.3'), isNull);
      expect(pickApkAsset(null, '1.1.3'), isNull);
      expect(pickApkAsset('not a list', '1.1.3'), isNull);
    });

    test('an asset with no download url is not offered', () {
      expect(
        pickApkAsset([
          {'name': 'Lekha-v1.1.3.apk'},
        ], '1.1.3'),
        isNull,
      );
    });

    test('reads the shape GitHub actually returns', () {
      final body =
          jsonDecode('''
        {"tag_name":"v1.1.3","assets":[
          {"name":"Lekha-v1.1.3.apk",
           "browser_download_url":"https://github.com/x/releases/download/v1.1.3/Lekha-v1.1.3.apk"}
        ]}
      ''')
              as Map<String, dynamic>;
      expect(
        pickApkAsset(body['assets'], '1.1.3'),
        endsWith('/Lekha-v1.1.3.apk'),
      );
    });
  });

  group('looksLikeApk', () {
    test('accepts a zip header, which is what an APK is', () {
      expect(looksLikeApk([0x50, 0x4B, 0x03, 0x04]), isTrue);
    });

    test('rejects an HTML body', () {
      // A captive portal or an error page would otherwise be handed to the
      // package installer as though it were an app.
      expect(looksLikeApk('<!DOCTYPE html>'.codeUnits), isFalse);
    });

    test('rejects an empty or truncated download', () {
      expect(looksLikeApk(const []), isFalse);
      expect(looksLikeApk([0x50]), isFalse);
    });
  });

  group('shouldPromptForUpdate', () {
    const release = AppRelease(version: '1.1.4', apkUrl: 'https://x/a.apk');

    test('prompts when a newer version exists and nothing was dismissed', () {
      expect(shouldPromptForUpdate(release, null), isTrue);
    });

    test('stays quiet once that version was dismissed', () {
      expect(shouldPromptForUpdate(release, '1.1.4'), isFalse);
    });

    test('speaks up again for a genuinely newer version', () {
      // Dismissing 1.1.4 must not silence 1.1.5.
      expect(shouldPromptForUpdate(release, '1.1.3'), isTrue);
    });

    test('nothing to say when up to date', () {
      expect(shouldPromptForUpdate(null, null), isFalse);
      expect(shouldPromptForUpdate(null, '1.1.4'), isFalse);
    });
  });
}
