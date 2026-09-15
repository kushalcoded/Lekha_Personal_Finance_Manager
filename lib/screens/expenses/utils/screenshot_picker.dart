import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/sms/screenshot_import.dart';
import '../../../providers/sms/sms_providers.dart';
import '../../../utils/formatters/formatters.dart';
import '../../../widgets/common/top_notice.dart';

/// Pick payment screenshots and add the payments in them to Detected.
///
/// The one import flow, shared by the Expenses app bar and the Detected
/// section. Says what it found either way, including when a screenshot could
/// not be read, so an empty result never looks like success.
Future<void> importPaymentScreenshots(WidgetRef ref) async {
  final files = await openFiles(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Screenshots',
        extensions: ['png', 'jpg', 'jpeg', 'webp', 'heic', 'heif'],
        mimeTypes: ['image/*'],
        uniformTypeIdentifiers: ['public.image'],
      ),
    ],
  );
  if (files.isEmpty) return;

  final count = files.length;
  showNotice(
    'Reading $count ${AppFormatters.plural(count, 'screenshot', 'screenshots')}…',
    duration: const Duration(seconds: 90),
  );

  final service = ref.read(smsCaptureServiceProvider);
  var found = 0;
  var added = 0;
  var unreadable = 0;
  final skipped = <AlreadyHere, int>{};
  for (final file in files) {
    try {
      final image = await shrinkForUpload(
        await file.readAsBytes(),
        file.mimeType ?? _mimeFromName(file.name),
      );
      final result = await service.importScreenshot(
        image.bytes,
        mimeType: image.mimeType,
      );
      found += result.found;
      added += result.added;
      for (final e in result.skipped.entries) {
        skipped[e.key] = (skipped[e.key] ?? 0) + e.value;
      }
    } catch (_) {
      unreadable++;
    }
  }

  final parts = <String>[
    if (found == 0 && unreadable == 0) 'No payments found in that screenshot',
    if (added > 0)
      'Added $added ${AppFormatters.plural(added, 'payment', 'payments')} '
          'to Detected',
    // Said by where, so it can be checked: a bare "10 already here" gave no
    // way to tell a correct match from a payment wrongly swallowed.
    if (skipped[AlreadyHere.waiting] case final n?) '$n already in Detected',
    if (skipped[AlreadyHere.added] case final n?)
      '$n already ${AppFormatters.plural(n, 'an expense', 'expenses')}',
    if (skipped[AlreadyHere.dismissed] case final n?) '$n dismissed before',
    if (unreadable > 0)
      '$unreadable could not be read — try a sharper screenshot',
  ];
  showNotice(parts.join(' · '));
}

/// Screenshots from a modern phone are several megabytes, most of it pixels
/// the model does not need to read a list of payments. Scaled down to
/// [maxWidth], they upload in seconds on a phone connection.
Future<({Uint8List bytes, String mimeType})> shrinkForUpload(
  Uint8List bytes,
  String mimeType, {
  int maxWidth = 1080,
}) async {
  try {
    final probe = await (await ui.instantiateImageCodec(bytes)).getNextFrame();
    final width = probe.image.width;
    probe.image.dispose();
    if (width <= maxWidth && bytes.length < 1500 * 1024) {
      return (bytes: bytes, mimeType: mimeType);
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: math.min(width, maxWidth),
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) return (bytes: bytes, mimeType: mimeType);
    return (bytes: data.buffer.asUint8List(), mimeType: 'image/png');
  } catch (_) {
    // A format this platform cannot decode (HEIC off Safari): send it as it
    // is and let the model try.
    return (bytes: bytes, mimeType: mimeType);
  }
}

String _mimeFromName(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    _ => 'image/png',
  };
}
