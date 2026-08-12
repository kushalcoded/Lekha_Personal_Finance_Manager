import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/update_providers.dart';
import '../../services/update/update_installer.dart';

/// Download and install a release without leaving the app.
///
/// Every failure path ends at the release page in a browser rather than a dead
/// end — this is a convenience over the manual route, not a replacement that
/// can strand the user on a version they can't upgrade.
Future<void> runAppUpdate(BuildContext context, AppRelease release) async {
  final url = release.apkUrl;
  if (url == null) {
    // Release published without an APK attached.
    await _openReleasePage();
    return;
  }

  final installer = UpdateInstaller();

  if (!await installer.canInstall()) {
    if (!context.mounted) return;
    final granted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow Lekha to install updates'),
        content: const Text(
          'Android asks once, per app. Turn on "Allow from this source" and '
          'come back — after that, updating is a single tap.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Use browser instead'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (granted != true) {
      await _openReleasePage();
      return;
    }
    await installer.requestInstallPermission();
    // The user is now in system settings; they'll tap Update again on return
    // rather than us guessing when the grant landed.
    return;
  }

  if (!context.mounted) return;
  final progress = ValueNotifier<double>(0);
  var dismissed = false;
  unawaitedDialog(context, release.version, progress, () => dismissed = true);

  try {
    final path = await installer.download(
      url,
      release.version,
      onProgress: (value) => progress.value = value,
    );
    if (context.mounted && !dismissed) Navigator.of(context).pop();
    await installer.install(path);
  } catch (error) {
    if (context.mounted && !dismissed) Navigator.of(context).pop();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Update failed: $error'),
        action: SnackBarAction(
          label: 'Browser',
          onPressed: _openReleasePage,
        ),
      ),
    );
  } finally {
    progress.dispose();
  }
}

Future<void> _openReleasePage() => launchUrl(
  Uri.parse(kReleasesLatestUrl),
  mode: LaunchMode.externalApplication,
);

/// Non-dismissible progress dialog; the download is short and cancelling
/// mid-write would leave a partial APK to clean up.
void unawaitedDialog(
  BuildContext context,
  String version,
  ValueNotifier<double> progress,
  VoidCallback onDismissed,
) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text('Downloading v$version'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: value == 0 ? null : value),
            const SizedBox(height: 10),
            Text(
              value == 0
                  ? 'Starting…'
                  : '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  ).then((_) => onDismissed());
}
