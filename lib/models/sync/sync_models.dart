import 'package:flutter/foundation.dart';

enum SyncEntityType { expense, receivable, payable, recurringTemplate }

@immutable
class SyncMetadata {
  final String entityId;
  final SyncEntityType entityType;
  final String userId;
  final DateTime updatedAt;
  final DateTime? syncedAt;
  final bool isDeleted;
  final String deviceId;

  const SyncMetadata({
    required this.entityId,
    required this.entityType,
    required this.userId,
    required this.updatedAt,
    required this.syncedAt,
    required this.isDeleted,
    required this.deviceId,
  });

  SyncMetadata copyWith({
    String? entityId,
    SyncEntityType? entityType,
    String? userId,
    DateTime? updatedAt,
    DateTime? syncedAt,
    bool? isDeleted,
    String? deviceId,
  }) {
    return SyncMetadata(
      entityId: entityId ?? this.entityId,
      entityType: entityType ?? this.entityType,
      userId: userId ?? this.userId,
      updatedAt: updatedAt ?? this.updatedAt,
      syncedAt: syncedAt ?? this.syncedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entityId': entityId,
      'entityType': entityType.name,
      'userId': userId,
      'updatedAt': updatedAt.toIso8601String(),
      'syncedAt': syncedAt?.toIso8601String(),
      'isDeleted': isDeleted,
      'deviceId': deviceId,
    };
  }

  static SyncMetadata fromJson(Map<dynamic, dynamic> json) {
    return SyncMetadata(
      entityId: json['entityId'] as String,
      entityType: SyncEntityType.values.firstWhere(
        (value) => value.name == json['entityType'],
        orElse: () => SyncEntityType.expense,
      ),
      userId: json['userId'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      syncedAt: json['syncedAt'] == null
          ? null
          : DateTime.parse(json['syncedAt'] as String),
      isDeleted: json['isDeleted'] as bool? ?? false,
      deviceId: json['deviceId'] as String? ?? 'unknown-device',
    );
  }
}

@immutable
class SyncState {
  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final DateTime? lastAttemptAt;
  final int uploadCount;
  final int downloadCount;
  final int pendingCount;
  final String status;
  final String? error;

  const SyncState({
    this.isSyncing = false,
    this.lastSyncedAt,
    this.lastAttemptAt,
    this.uploadCount = 0,
    this.downloadCount = 0,
    this.pendingCount = 0,
    this.status = 'Idle',
    this.error,
  });

  SyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncedAt,
    DateTime? lastAttemptAt,
    int? uploadCount,
    int? downloadCount,
    int? pendingCount,
    String? status,
    String? error,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      uploadCount: uploadCount ?? this.uploadCount,
      downloadCount: downloadCount ?? this.downloadCount,
      pendingCount: pendingCount ?? this.pendingCount,
      status: status ?? this.status,
      error: error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isSyncing': isSyncing,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      'uploadCount': uploadCount,
      'downloadCount': downloadCount,
      'pendingCount': pendingCount,
      'status': status,
      'error': error,
    };
  }

  static SyncState fromJson(Map<dynamic, dynamic> json) {
    return SyncState(
      isSyncing: json['isSyncing'] as bool? ?? false,
      lastSyncedAt: json['lastSyncedAt'] == null
          ? null
          : DateTime.parse(json['lastSyncedAt'] as String),
      lastAttemptAt: json['lastAttemptAt'] == null
          ? null
          : DateTime.parse(json['lastAttemptAt'] as String),
      uploadCount: (json['uploadCount'] as num?)?.toInt() ?? 0,
      downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'Idle',
      error: json['error'] as String?,
    );
  }
}

@immutable
class SyncResult {
  final int uploadCount;
  final int downloadCount;
  final DateTime completedAt;
  final String status;
  final String? error;

  const SyncResult({
    required this.uploadCount,
    required this.downloadCount,
    required this.completedAt,
    required this.status,
    this.error,
  });
}
