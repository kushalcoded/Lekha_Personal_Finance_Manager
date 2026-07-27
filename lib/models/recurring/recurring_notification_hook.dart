import 'package:flutter/foundation.dart';

enum RecurringNotificationType { dueToday, upcoming, overdue }

@immutable
class RecurringNotificationHook {
  final String templateId;
  final DateTime dueAt;
  final RecurringNotificationType type;
  final String title;
  final String message;

  const RecurringNotificationHook({
    required this.templateId,
    required this.dueAt,
    required this.type,
    required this.title,
    required this.message,
  });
}
