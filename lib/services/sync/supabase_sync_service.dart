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
          remote != null && remoteIsNewer(remote.updatedAt, lastSynced);
      final localEmpty = _localIsEmpty(userId);
      // Unsynced local edits (e.g. an expense added seconds ago, still inside
      // the push debounce) must never be overwritten by a pull — push wins.
      final mutatedAt = _hiveService.lastLocalMutationAt;
      final localDirty =
          mutatedAt != null &&
          (lastSynced == null || mutatedAt.toUtc().isAfter(lastSynced.toUtc()));

      var uploads = 0;
      var downloads = 0;
      DateTime marker;

      // `remote != null` inline so the branch keeps its null promotion.
      if (remote != null &&
          shouldPull(
            pushOnly: pushOnly,
            hasRemote: true,
            remoteNewer: remoteNewer,
            localEmpty: localEmpty,
            localDirty: localDirty,
          )) {
        // PULL: adopt the cloud snapshot wholesale. If it holds fewer records
        // than we do, stash what's here first so the data is recoverable from
        // Settings even if the cloud copy turns out to be the wrong one.
        if (_wouldLoseRecords(remote.snapshot, userId)) {
          await _hiveService.saveLocalBackup(
            _hiveService.createLocalBackupSnapshot(userId),
          );
        }
        await _hiveService.restoreFromBackup(remote.snapshot);
        downloads = 1;
        marker = remote.updatedAt;
      } else {
        // PUSH — but first fold in any detected-SMS state the other device
        // pushed since our last pull; a wholesale upload would silently
        // drop it. Counted as a download so the UI refreshes.
        if (remote != null) {
          final merged = await _hiveService.mergeRemotePending(remote.snapshot);
          if (merged) downloads = 1;
        }
        if (remote != null &&
            refuseEmptyPush(
              localEmpty: _localIsEmpty(userId),
              remoteHasData: !_snapshotIsEmpty(remote.snapshot),
              localDirty: localDirty,
            )) {
          throw StateError(
            'Refused to upload an empty snapshot over cloud data. Your data '
            'is safe in the cloud — reopen the app, and use Settings → sync '
            'if you meant to clear it.',
          );
        }
        // Emptying the account on purpose IS allowed above, so keep the copy
        // we are about to overwrite. Restoring it from Settings is then the
        // undo for "I deleted the last thing and meant to keep it".
        if (remote != null &&
            _localIsEmpty(userId) &&
            !_snapshotIsEmpty(remote.snapshot)) {
          await _hiveService.saveLocalBackup(remote.snapshot);
        }
        marker = await _uploadSnapshot(userId);
        uploads = 1;
        // Everything local now exists in the cloud, so a later pull is safe.
        // Leaving the marker set would block every future pull.
        await _hiveService.clearLocalMutationMarker();
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
    // UTC, so the ISO string carries a 'Z'. Sending local wall time with no
    // offset into a timestamptz column made Postgres read it as UTC, so every
    // snapshot came back one UTC offset in the future — the remote always
    // looked newer, and every cold start pulled and overwrote local data.
    final now = DateTime.now().toUtc();
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
        DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return _RemoteSnapshot(Map<String, dynamic>.from(snap), updatedAt);
  }

  /// Whether the cloud snapshot post-dates what this device last synced.
  ///
  /// Compares instants, never wall-clock strings. Both sides are normalised to
  /// UTC because they arrive in different shapes: the remote is timezone-aware
  /// from Postgres, while a `lastSyncedAt` written by an older build is a naive
  /// local string. Dart parses that as local time, which is the instant that
  /// was meant — so converting is safe, and forcing UTC on it would shift every
  /// stored value by the device's offset.
  /// Adopt the cloud copy wholesale, rather than uploading ours?
  ///
  /// `localDirty` vetoes a pull outright. It used to be `!localDirty ||
  /// localEmpty`, and `localEmpty` is exactly what deleting your last record
  /// makes you: the device looked factory-fresh, pulled, and the record came
  /// back — reproducible by deleting the only expense in an account. Offline
  /// the same delete stuck, which is what gave the game away.
  static bool shouldPull({
    required bool pushOnly,
    required bool hasRemote,
    required bool remoteNewer,
    required bool localEmpty,
    required bool localDirty,
  }) {
    if (pushOnly || !hasRemote || localDirty) return false;
    return remoteNewer || localEmpty;
  }

  /// Block an upload that would flatten a populated cloud from an empty device.
  ///
  /// Aimed at accidents — a concurrent restore, a failed load — which never
  /// touch the mutation marker. A deliberate delete does, so [localDirty]
  /// lets a real "I removed everything" through instead of stranding the
  /// device in a sync that can never succeed.
  static bool refuseEmptyPush({
    required bool localEmpty,
    required bool remoteHasData,
    required bool localDirty,
  }) {
    return localEmpty && remoteHasData && !localDirty;
  }

  static bool remoteIsNewer(DateTime remoteUpdatedAt, DateTime? lastSynced) {
    if (lastSynced == null) return true;
    return remoteUpdatedAt.toUtc().isAfter(lastSynced.toUtc());
  }

  bool _localIsEmpty(String userId) {
    return _hiveService.getAllExpenses(userId).isEmpty &&
        _hiveService.getAllReceivables(userId).isEmpty &&
        _hiveService.getAllPayables(userId).isEmpty &&
        _hiveService.getRecurringTemplates(userId).isEmpty;
  }

  /// Same question, asked of a snapshot rather than the local boxes. Public
  /// for the guard's regression test — this is the check that stands between
  /// a momentarily-empty device and every device's data.
  static bool snapshotIsEmpty(Map<String, dynamic> snapshot) =>
      _snapshotIsEmpty(snapshot);

  static bool _snapshotIsEmpty(Map<String, dynamic> snapshot) {
    int count(String key) {
      final value = snapshot[key];
      return value is List ? value.length : 0;
    }

    return count('expenses') == 0 &&
        count('receivables') == 0 &&
        count('payables') == 0 &&
        count('recurringTemplates') == 0;
  }

  /// True when adopting [snapshot] would drop money records this device has.
  bool _wouldLoseRecords(Map<String, dynamic> snapshot, String userId) {
    int count(String key) {
      final value = snapshot[key];
      return value is List ? value.length : 0;
    }

    return count('expenses') < _hiveService.getAllExpenses(userId).length ||
        count('receivables') < _hiveService.getAllReceivables(userId).length ||
        count('payables') < _hiveService.getAllPayables(userId).length;
  }
}

class _RemoteSnapshot {
  final Map<String, dynamic> snapshot;
  final DateTime updatedAt;

  const _RemoteSnapshot(this.snapshot, this.updatedAt);
}
