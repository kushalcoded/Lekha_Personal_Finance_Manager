import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/sync/sync_models.dart';
import '../storage/hive_service.dart';
import '../supabase/supabase_service.dart';

/// Whole-account sync via a single JSON snapshot per user.
///
/// Instead of syncing each entity table (which kept losing newly-added fields),
/// we push the exact same backup snapshot that Export/Import uses — so
/// EVERYTHING travels: expenses, receivables, payables, recurring, budgets,
/// salary cycles + history, categories, pending SMS, settings, onboarding.
///
/// ponytail: last-write-wins on the WHOLE snapshot (no per-record merge). Fine
/// for one user across a couple of devices used one-at-a-time; if two devices
/// edit offline simultaneously, the next sync keeps the newer snapshot and
/// drops the other's unsynced edits. Upgrade to per-entity CRDT merge only if
/// real concurrent multi-device editing shows up.
class SupabaseSyncService {
  static const String _table = 'user_backups';

  final HiveService _hiveService;
  final SupabaseClient _client;

  SupabaseSyncService({HiveService? hiveService, SupabaseClient? client})
    : _hiveService = hiveService ?? HiveService(),
      _client = client ?? SupabaseService.client;

  /// Pull if the cloud snapshot is newer than our last sync (or this device has
  /// no data yet); otherwise push the local snapshot up. Pass [pushOnly] when
  /// the local side is the fresh editor (e.g. app going to background) so a
  /// concurrent cloud change doesn't clobber what the user just did.
  Future<SyncResult> syncUser(String userId, {bool pushOnly = false}) async {
    final startedAt = DateTime.now();
    final initial = _hiveService.getSyncState(userId);
    await _hiveService.saveSyncState(
      userId,
      initial.copyWith(
        isSyncing: true,
        lastAttemptAt: startedAt,
        status: 'Syncing...',
        error: null,
      ),
    );

    try {
      final remote = await _fetchRemoteSnapshot(userId);
      final lastSynced = initial.lastSyncedAt;
      final remoteNewer =
          remote != null &&
          (lastSynced == null || remote.updatedAt.isAfter(lastSynced));
      final localEmpty = _localIsEmpty(userId);

      var uploads = 0;
      var downloads = 0;
      DateTime marker;

      if (!pushOnly && remote != null && (remoteNewer || localEmpty)) {
        // PULL: adopt the cloud snapshot wholesale.
        await _hiveService.restoreFromBackup(remote.snapshot);
        downloads = 1;
        marker = remote.updatedAt;
      } else {
        // PUSH: send our snapshot up.
        marker = await _uploadSnapshot(userId);
        uploads = 1;
      }

      final completedAt = DateTime.now();
      await _saveSynced(userId, startedAt, marker, uploads, downloads);
      return SyncResult(
        uploadCount: uploads,
        downloadCount: downloads,
        completedAt: completedAt,
        status: 'Synced',
      );
    } catch (e) {
      await _hiveService.saveSyncState(
        userId,
        initial.copyWith(
          isSyncing: false,
          lastAttemptAt: startedAt,
          status: 'Sync failed',
          error: e.toString(),
        ),
      );
      return SyncResult(
        uploadCount: 0,
        downloadCount: 0,
        completedAt: DateTime.now(),
        status: 'Sync failed',
        error: e.toString(),
      );
    }
  }

  /// Force-upload the local snapshot (used by the sign-in reconciler when the
  /// user chose "keep this device").
  Future<void> pushSnapshot(String userId) async {
    final startedAt = DateTime.now();
    final marker = await _uploadSnapshot(userId);
    await _saveSynced(userId, startedAt, marker, 1, 0);
  }

  /// Force-download and restore the cloud snapshot ("keep cloud" / new device).
  /// No-op if there's nothing in the cloud yet.
  Future<void> pullSnapshot(String userId) async {
    final startedAt = DateTime.now();
    final remote = await _fetchRemoteSnapshot(userId);
    if (remote == null) return;
    await _hiveService.restoreFromBackup(remote.snapshot);
    await _saveSynced(userId, startedAt, remote.updatedAt, 0, 1);
  }

  Future<bool> remoteExists(String userId) async =>
      (await _fetchRemoteSnapshot(userId)) != null;

  Future<DateTime> _uploadSnapshot(String userId) async {
    final snapshot = _hiveService.createLocalBackupSnapshot(userId);
    final now = DateTime.now();
    await _client.from(_table).upsert({
      'user_id': userId,
      'snapshot': snapshot,
      'updated_at': now.toIso8601String(),
    });
    return now;
  }

  Future<void> _saveSynced(
    String userId,
    DateTime startedAt,
    DateTime marker,
    int uploads,
    int downloads,
  ) async {
    await _hiveService.saveSyncState(
      userId,
      SyncState(
        isSyncing: false,
        lastSyncedAt: marker,
        lastAttemptAt: startedAt,
        uploadCount: uploads,
        downloadCount: downloads,
        status: 'Synced',
      ),
    );
  }

  Future<_RemoteSnapshot?> _fetchRemoteSnapshot(String userId) async {
    final rows = await _client
        .from(_table)
        .select('snapshot, updated_at')
        .eq('user_id', userId)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    final snap = row['snapshot'];
    if (snap is! Map) return null;
    final updatedAt =
        DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return _RemoteSnapshot(Map<String, dynamic>.from(snap), updatedAt);
  }

  bool _localIsEmpty(String userId) {
    return _hiveService.getAllExpenses(userId).isEmpty &&
        _hiveService.getAllReceivables(userId).isEmpty &&
        _hiveService.getAllPayables(userId).isEmpty &&
        _hiveService.getRecurringTemplates(userId).isEmpty;
  }
}

class _RemoteSnapshot {
  final Map<String, dynamic> snapshot;
  final DateTime updatedAt;

  const _RemoteSnapshot(this.snapshot, this.updatedAt);
}
