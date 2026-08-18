import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One daily nudge about money that needs attention, delivered while the app
/// is closed — the dashboard card only speaks to someone already looking at it.
///
/// Backed by AlarmManager in `ReminderReceiver.kt`, not a notifications
/// package: the app already owns a notification channel and a POST_NOTIFICATIONS
/// flow for SMS detection, and one repeating reminder didn't justify two more
/// dependencies plus core library desugaring.
///
/// Deliberately **one** notification carrying a summary, rescheduled from
/// scratch whenever the app has fresh data, rather than one per debt. Five
/// buzzes for five receivables is how a reminder becomes something you swipe
/// away unread.
class ReminderNotifications {
  static const _channel = MethodChannel('lekha/reminders');

  /// Android only. The PWA has no alarm to set and no channel to call.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Store the wording and arm the next alarm. Returns false when Android
  /// won't let the app post — the alarm still fires, it just stays silent, so
  /// the caller can say so instead of leaving a switch on that does nothing.
  ///
  /// ponytail: the text is a snapshot from the last time the app ran. Settle a
  /// debt on another device and never open this one and the nudge repeats with
  /// stale wording until you do. Per-debt scheduling with a background refresh
  /// is the upgrade, if that ever actually bites.
  static Future<bool> scheduleDaily({
    required String title,
    required String body,
    int hour = 9,
  }) async {
    if (!supported) return false;
    try {
      final granted = await _channel.invokeMethod<bool>('schedule', {
        'title': title,
        'body': body,
        'hour': hour,
      });
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> cancel() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } on PlatformException {
      // Nothing scheduled, or the channel isn't there. Either way, silence is
      // the outcome we wanted.
    }
  }

  /// Android 13+ posts nothing without this.
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
