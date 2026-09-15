import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sync/sync_providers.dart';
import 'top_notice.dart';

/// Run a sync and say what happened.
///
/// Every Sync button goes through this. The one on Expenses used to run
/// silently, and a sync that did nothing looked exactly like one that worked —
/// which is how "Already up to date" hid a phone that had stopped pulling.
Future<void> syncWithFeedback(WidgetRef ref) async {
  final result = await ref.read(syncProvider.notifier).syncNow();
  final changed = result.uploadCount + result.downloadCount;
  showNotice(
    result.error != null
        ? 'Sync failed — ${result.error}'
        : changed == 0
        ? 'Already up to date'
        : 'Synced · $changed ${changed == 1 ? 'change' : 'changes'}',
    actionLabel: result.error == null ? null : 'Retry',
    onAction: result.error == null ? null : () => syncWithFeedback(ref),
  );
}
