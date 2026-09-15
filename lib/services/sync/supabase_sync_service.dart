import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/sync/sync_models.dart';
import '../storage/hive_service.dart';
import '../supabase/supabase_service.dart';
import 'snapshot_merge.dart';

/// Whole-account sync via a single JSON snapshot per user.
///
/// Instead of syncing each entity table (which kept losing newly-added fields),
/// we push the exact same backup snapshot that Export/Import uses — so
/// EVERYTHING travels: expenses, receivables, payables, recurring, budgets,
/// salary cycles + history, categories, pending SMS, settings, onboarding.
///
/// A device uploads only what it changed and pulls only what it lacks; see
/// [SupabaseSyncService.decide].
class SupabaseSyncService {
  static const String _table = 'user_backups';

  /// Generous for a whole-account snapshot on a slow connection, and far short
  /// of the OS TCP timeout. Without it a connected-but-dead network (captive
  /// portal, one bar) sails past the 6s health probe and then hangs for
  /// minutes with the sync button inert — every further tap attaches to the
  /// same stuck future rather than starting a new one.
  static const Duration _netTimeout = Duration(seconds: 30);

  static Never _timedOut() => throw Exception(
    'The server took too long to answer. Check your connection and try again.',
  );

  final HiveService _hiveService;
  final SupabaseClient _client;

  SupabaseSyncService({HiveService? hiveService, SupabaseClient? client})
    : _hiveService = hiveService ?? HiveService(),
      _client = client ?? SupabaseService.client;

  /// Decide what this device and the cloud each have that the other lacks,
  /// then do only that — see [decide]. [pushOnly] is for moments the UI must
  /// not change underneath the user (leaving the app, the edit debounce): it
  /// still uploads real edits, but never pulls.
  Future<SyncResult> syncUser(
    String userId, {
    bool pushOnly = false,
    bool isRetry = false,
  }) async {
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

    var detail = '';
    try {
      final remote = await _fetchRemoteSnapshot(userId);
      // Builds before this field existed stored the same server stamp in
      // lastSyncedAt, so it is the right fallback for a first run after update.
      final stamp = initial.remoteUpdatedAt ?? initial.lastSyncedAt;
      final changed = remote != null && remoteChanged(remote.updatedAt, stamp);
      final localEmpty = _localIsEmpty(userId);
      // Dirty means "has edits the cloud has not seen", full stop. Comparing
      // the mutation time with lastSyncedAt put another device's clock into
      // the question after every pull.
      final localDirty = _hiveService.lastLocalMutationAt != null;
      final action = decide(
        pushOnly: pushOnly,
        hasRemote: remote != null,
        remoteChanged: changed,
        localEmpty: localEmpty,
        localDirty: localDirty,
        matchesCloud: remote == null || _sameCounts(remote.snapshot, userId),
      );
      detail = [
        '${pushOnly ? 'Leaving the app' : 'Full sync'} → ${action.name}',
        'This device: ${localDirty ? 'had unsynced edits' : 'no unsynced edits'}'
            ', ${_hiveService.getAllExpenses(userId).length} expenses',
        remote == null
            ? 'Cloud: empty'
            : 'Cloud: ${changed ? 'changed' : 'unchanged'}, '
                  '${(remote.snapshot['expenses'] as List?)?.length ?? 0} '
                  'expenses',
        'Cloud version ${_stampText(remote?.updatedAt)}',
        'Last seen here ${_stampText(stamp)}',
      ].join('\n');
      debugPrint('[sync] ${detail.replaceAll('\n', ' | ')}');

      var uploads = 0;
      var downloads = 0;
      // What this device has actually taken in. Only a pull or an upload moves
      // it; see [stampAfterSkip].
      DateTime? serverStamp = stampAfterSkip(
        previous: stamp,
        remote: remote?.updatedAt,
        remoteChanged: changed,
      );

      switch (action) {
        case SyncAction.nothing:
          break;
        case SyncAction.pull:
          // Adopt the cloud snapshot wholesale. If it holds fewer records than
          // we do, stash what's here first so the data is recoverable from
          // Settings even if the cloud copy turns out to be the wrong one.
          if (_wouldLoseRecords(remote!.snapshot, userId)) {
            await _hiveService.saveLocalBackup(
              _hiveService.createLocalBackupSnapshot(userId),
            );
          }
          await _hiveService.restoreFromBackup(remote.snapshot);
          serverStamp = remote.updatedAt;
          downloads = 1;
        case SyncAction.merge:
        case SyncAction.upload:
          // Read before anything is snapshotted: an edit made from here on is
          // not in what we upload, and must leave the device dirty.
          final seq = _hiveService.mutationSeq;
          if (remote != null) {
            // Fold in detected-SMS state the other device pushed since our
            // last pull; a wholesale upload would silently drop it. Counted as
            // a download so the UI refreshes.
            final merged = await _hiveService.mergeRemotePending(
              remote.snapshot,
            );
            if (merged) downloads = 1;
            if (action == SyncAction.merge) {
              // Both sides changed. Keep every record either side added, honour
              // deletions and the newer edit, then upload the result — rather
              // than one side's snapshot silently replacing the other's.
              await _hiveService.applyMergedSnapshot(
                mergeSnapshots(
                  _hiveService.createLocalBackupSnapshot(userId),
                  remote.snapshot,
                ),
                userId,
              );
              downloads = 1;
            }
            if (refuseEmptyPush(
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
            // Emptying the account on purpose IS allowed above, so keep the
            // copy we are about to overwrite. Restoring it from Settings is
            // then the undo for "I deleted the last thing and meant to keep it".
            if (_localIsEmpty(userId) && !_snapshotIsEmpty(remote.snapshot)) {
              await _hiveService.saveLocalBackup(remote.snapshot);
            }
          }
          serverStamp = await _uploadSnapshot(
            userId,
            expectedRaw: remote?.rawUpdatedAt,
          );
          uploads = 1;
          // Everything up to [seq] is now in the cloud, so a later pull is
          // safe. An edit made during the upload keeps the device dirty.
          await _hiveService.clearLocalMutationMarker(ifSeq: seq);
      }

      final completedAt = DateTime.now();
      await _saveSynced(
        userId,
        startedAt,
        serverStamp,
        uploads,
        downloads,
        detail:
            '$detail\nResult: $uploads up, $downloads down, now at '
            '${_stampText(serverStamp)}',
      );
      return SyncResult(
        uploadCount: uploads,
        downloadCount: downloads,
        completedAt: completedAt,
        status: 'Synced',
      );
    } on _CloudMovedOn {
      // Another device wrote between our read and our write. Our upload was
      // refused rather than landing on top of theirs; start over from the
      // copy that is actually there now.
      if (!isRetry) {
        return syncUser(userId, pushOnly: pushOnly, isRetry: true);
      }
      return _failed(
        userId,
        initial,
        startedAt,
        'Another device is syncing at the same time. Try again in a moment.',
      );
    } catch (e) {
      debugPrint('[sync] failed: $e');
      return _failed(
        userId,
        initial,
        startedAt,
        e.toString(),
        detail: '$detail\nFailed: $e',
      );
    }
  }

  Future<SyncResult> _failed(
    String userId,
    SyncState initial,
    DateTime startedAt,
    String error, {
    String? detail,
  }) async {
    await _hiveService.saveSyncState(
      userId,
      initial.copyWith(
        isSyncing: false,
        lastAttemptAt: startedAt,
        status: 'Sync failed',
        error: error,
        detail: detail,
      ),
    );
    return SyncResult(
      uploadCount: 0,
      downloadCount: 0,
      completedAt: DateTime.now(),
      status: 'Sync failed',
      error: error,
    );
  }

  /// Force-upload the local snapshot (used by the sign-in reconciler when the
  /// user chose "keep this device").
  Future<void> pushSnapshot(String userId) async {
    final startedAt = DateTime.now();
    final seq = _hiveService.mutationSeq;
    final stamp = await _uploadSnapshot(userId, force: true);
    await _hiveService.clearLocalMutationMarker(ifSeq: seq);
    await _saveSynced(userId, startedAt, stamp, 1, 0);
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

  /// Upload and return the `updated_at` the server stored.
  ///
  /// Compare-and-swap: with [expectedRaw] the write only lands if the row
  /// still carries the stamp we read, and with none it only lands if there is
  /// no row yet. Either way a device that raced us makes this throw
  /// [_CloudMovedOn] instead of silently overwriting it. [force] is the
  /// sign-in reconciler's explicit "keep this device", which means overwrite.
  Future<DateTime> _uploadSnapshot(
    String userId, {
    String? expectedRaw,
    bool force = false,
  }) async {
    final snapshot = _hiveService.createLocalBackupSnapshot(userId);
    // UTC, so the ISO string carries a 'Z'. Sending local wall time with no
    // offset into a timestamptz column made Postgres read it as UTC, so every
    // snapshot came back one UTC offset in the future — the remote always
    // looked newer, and every cold start pulled and overwrote local data.
    final row = {
      'user_id': userId,
      'snapshot': snapshot,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final List<dynamic> written;
    try {
      if (force) {
        written = await _client
            .from(_table)
            .upsert(row)
            .select('updated_at')
            .timeout(_netTimeout, onTimeout: _timedOut);
      } else if (expectedRaw != null) {
        written = await _client
            .from(_table)
            .update(row)
            .eq('user_id', userId)
            .eq('updated_at', expectedRaw)
            .select('updated_at')
            .timeout(_netTimeout, onTimeout: _timedOut);
      } else {
        written = await _client
            .from(_table)
            .insert(row)
            .select('updated_at')
            .timeout(_netTimeout, onTimeout: _timedOut);
      }
    } on PostgrestException catch (e) {
      // 23505: another device created the row first.
      if (e.code == '23505') throw const _CloudMovedOn();
      rethrow;
    }
    if (written.isEmpty) throw const _CloudMovedOn();
    final stored = DateTime.tryParse('${written.first['updated_at']}')?.toUtc();
    if (stored == null) {
      throw StateError('The server did not confirm the sync.');
    }
    return stored;
  }

  Future<void> _saveSynced(
    String userId,
    DateTime startedAt,
    DateTime? serverStamp,
    int uploads,
    int downloads, {
    String? detail,
  }) async {
    await _hiveService.saveSyncState(
      userId,
      SyncState(
        isSyncing: false,
        lastSyncedAt: DateTime.now().toUtc(),
        remoteUpdatedAt: serverStamp,
        lastAttemptAt: startedAt,
        uploadCount: uploads,
        downloadCount: downloads,
        status: 'Synced',
        detail: detail,
      ),
    );
  }

  static String _stampText(DateTime? at) =>
      at == null ? 'none' : at.toUtc().toIso8601String();

  Future<_RemoteSnapshot?> _fetchRemoteSnapshot(String userId) async {
    final rows = await _client
        .from(_table)
        .select('snapshot, updated_at')
        .eq('user_id', userId)
        .limit(1)
        .timeout(_netTimeout, onTimeout: _timedOut);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    final snap = row['snapshot'];
    if (snap is! Map) return null;
    final raw = row['updated_at']?.toString() ?? '';
    final updatedAt =
        DateTime.tryParse(raw)?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return _RemoteSnapshot(Map<String, dynamic>.from(snap), updatedAt, raw);
  }

  /// What a sync should do, given what each side has.
  ///
  /// The rule that caused real data loss was "upload whenever pushing": a
  /// phone that had not been opened in a day uploaded its stale copy on the
  /// way to the background, and the web app's next sync pulled that over the
  /// expenses it had just added. Now a device uploads only what it changed,
  /// and a device that changed nothing takes what the cloud has.
  static SyncAction decide({
    required bool pushOnly,
    required bool hasRemote,
    required bool remoteChanged,
    required bool localEmpty,
    required bool localDirty,
    bool matchesCloud = true,
  }) {
    if (!hasRemote) return SyncAction.upload;
    if (localDirty) return remoteChanged ? SyncAction.merge : SyncAction.upload;
    if (pushOnly) return SyncAction.nothing;
    // A device that just deleted its last record is dirty and never gets
    // here, so an empty device pulling is only ever a fresh one.
    if (remoteChanged || localEmpty) return SyncAction.pull;
    // A device with no edits of its own should hold exactly what the cloud
    // holds. If the counts disagree it has missed something — however it came
    // to believe it was up to date — so it takes the cloud copy anyway.
    if (!matchesCloud) return SyncAction.pull;
    return SyncAction.nothing;
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

  /// The cloud stamp to remember when this sync takes nothing in.
  ///
  /// A push-only sync that finds the cloud changed skips the download — and
  /// used to record the new stamp anyway, as if it had been read. From then on
  /// that device believed it was up to date and never pulled what another
  /// device had written: an expense added on the web never reached a phone
  /// that happened to leave the app just after. Skipped means not seen, so the
  /// old stamp stays until something actually pulls it.
  static DateTime? stampAfterSkip({
    required DateTime? previous,
    required DateTime? remote,
    required bool remoteChanged,
  }) => remoteChanged ? previous : (remote ?? previous);

  /// Has anyone written to the cloud since this device last synced?
  ///
  /// [stamp] is the server's own `updated_at` from our last sync, so this is
  /// an equality test and no device's clock is ever compared with another's.
  /// `isAtSameMomentAs`, not `==`: `==` also compares the UTC flag, and a
  /// legacy stamp stored as naive local time would then always look changed.
  static bool remoteChanged(DateTime remoteUpdatedAt, DateTime? stamp) {
    if (stamp == null) return true;
    return !remoteUpdatedAt.isAtSameMomentAs(stamp);
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

  /// Whether this device holds as many money records as [snapshot].
  bool _sameCounts(Map<String, dynamic> snapshot, String userId) {
    int count(String key) {
      final value = snapshot[key];
      return value is List ? value.length : 0;
    }

    return count('expenses') == _hiveService.getAllExpenses(userId).length &&
        count('receivables') == _hiveService.getAllReceivables(userId).length &&
        count('payables') == _hiveService.getAllPayables(userId).length &&
        count('recurringTemplates') ==
            _hiveService.getRecurringTemplates(userId).length;
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

enum SyncAction { nothing, upload, pull, merge }

class _RemoteSnapshot {
  final Map<String, dynamic> snapshot;
  final DateTime updatedAt;

  /// Exactly as Postgres sent it, for the compare-and-swap filter. Re-encoding
  /// the parsed value could round away the microseconds and never match.
  final String rawUpdatedAt;

  const _RemoteSnapshot(this.snapshot, this.updatedAt, this.rawUpdatedAt);
}

class _CloudMovedOn implements Exception {
  const _CloudMovedOn();
}
