import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/sync/sync_models.dart';
import '../../screens/settings/providers/settings_providers.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/storage/hive_service.dart';
import '../../services/sync/supabase_sync_service.dart';
import '../auth/auth_provider.dart';
import '../sms/sms_providers.dart';
import '../storage/storage_providers.dart';

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  final HiveService _hiveService;
  final SupabaseSyncService _syncService;
  final ConnectivityService _connectivityService;

  SyncNotifier(this._ref, this._hiveService)
    : _syncService = SupabaseSyncService(hiveService: _hiveService),
      _connectivityService = ConnectivityService(),
      super(const SyncState());

  /// Get current authenticated user ID
  String? _getUserId() {
    return _ref.read(currentUserIdProvider);
  }

  /// The sync currently running, if any. Two syncs at once is how data got
  /// lost: one clears the boxes to restore a pull while the other snapshots
  /// them mid-clear and uploads that empty result. Taps coalesce onto the
  /// in-flight run instead.
  Future<SyncResult>? _inFlight;

  /// Perform full sync now. [pushOnly] forces an upload (used when the local
  /// side is the fresh editor, e.g. app going to background) so a concurrent
  /// cloud change doesn't overwrite what the user just did.
  Future<SyncResult> syncNow({bool pushOnly = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _syncNow(pushOnly: pushOnly);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<SyncResult> _syncNow({bool pushOnly = false}) async {
    final userId = _getUserId();
    if (userId == null || userId.isEmpty) {
      state = state.copyWith(
        isSyncing: false,
        status: 'Not authenticated',
        error: 'Please log in to sync data',
      );
      return SyncResult(
        uploadCount: 0,
        downloadCount: 0,
        completedAt: DateTime.now(),
        status: 'Not authenticated',
        error: 'User not authenticated',
      );
    }

    final authState = _ref.read(authStateProvider);
    if (!authState.isAuthenticated) {
      state = _hiveService
          .getSyncState(userId)
          .copyWith(isSyncing: false, status: 'Local only', error: null);
      return SyncResult(
        uploadCount: 0,
        downloadCount: 0,
        completedAt: DateTime.now(),
        status: 'Local only',
      );
    }

    // Check connectivity
    final isOnline = await _connectivityService.isOnline();
    if (!isOnline) {
      state = state.copyWith(
        isSyncing: false,
        status: 'Offline',
        error: 'No internet connection',
      );
      return SyncResult(
        uploadCount: 0,
        downloadCount: 0,
        completedAt: DateTime.now(),
        status: 'Offline',
        error: 'No internet connection',
      );
    }

    try {
      final result = await _syncService.syncUser(userId, pushOnly: pushOnly);
      state = _hiveService.getSyncState(userId);
      if (result.downloadCount > 0) await _refreshLocalStores(userId);
      return result;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        status: 'Sync failed',
        error: e.toString(),
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

  /// Does the signed-in account already have a cloud snapshot? Used by the
  /// sign-in reconciler to detect the local-vs-cloud conflict.
  Future<bool> hasRemote() async {
    final userId = _getUserId();
    if (userId == null || userId.isEmpty) return false;
    if (!await _connectivityService.isOnline()) return false;
    try {
      return await _syncService.remoteExists(userId);
    } catch (_) {
      return false;
    }
  }

  /// Reconciler action: overwrite the cloud with this device's data.
  Future<void> forcePush() async {
    final userId = _getUserId();
    if (userId == null || userId.isEmpty) return;
    await _syncService.pushSnapshot(userId);
    state = _hiveService.getSyncState(userId);
  }

  /// Reconciler action: overwrite this device with the cloud snapshot.
  Future<void> forcePull() async {
    final userId = _getUserId();
    if (userId == null || userId.isEmpty) return;
    await _syncService.pullSnapshot(userId);
    state = _hiveService.getSyncState(userId);
    await _refreshLocalStores(userId);
  }

  /// Refresh current sync status
  Future<void> refreshStatus() async {
    final userId = _getUserId();
    if (userId != null && userId.isNotEmpty) {
      state = _hiveService.getSyncState(userId);
    }
  }

  /// Auto-sync on app startup
  Future<void> autoSyncOnStartup() async {
    final userId = _getUserId();
    if (userId == null || userId.isEmpty) {
      return;
    }
    if (!_ref.read(authStateProvider).isAuthenticated) {
      await refreshStatus();
      return;
    }

    // Don't block the UI; run in background
    Future.microtask(() => syncNow());
  }

  /// Refresh local stores after a download pulled a new snapshot in. Covers
  /// everything the snapshot restores — money entities, settings/budget/cycles,
  /// and pending SMS — so the UI reflects the synced-in data immediately.
  Future<void> _refreshLocalStores(String userId) async {
    await Future.wait([
      _ref.read(expensesProvider.notifier).fetchExpenses(userId),
      _ref.read(receivablesProvider.notifier).fetchReceivables(userId),
      _ref.read(payablesProvider.notifier).fetchPayables(userId),
      _ref.read(recurringTemplatesProvider.notifier).fetchTemplates(userId),
      _ref.read(settingsProvider.notifier).loadSettings(),
    ]);
    _ref.read(pendingTransactionsProvider.notifier).refresh();
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  final hiveService = ref.watch(hiveServiceProvider);
  return SyncNotifier(ref, hiveService);
});
