import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sync/sync_providers.dart';
import '../../widgets/common/form_bits.dart';

/// Shown while the cloud snapshot is being written over this device.
///
/// Blocking on purpose, and the only place in the app that blocks. A restore
/// clears every box and refills it, so a half-finished one is a ledger with
/// some of your money missing — and the natural thing to do while staring at
/// an empty dashboard is to start typing it back in, which is exactly the
/// worst move. This is also the moment the app looks most broken: a fresh
/// install, no data yet, and a long silent wait.
class RestoringDialog extends ConsumerWidget {
  const RestoringDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Only trust the stage while a sync is actually running. SyncState.status
    // sits at 'Idle' the rest of the time, including in the moment between
    // this dialog appearing and the pull starting — and "IDLE" on a restore
    // screen reads as a broken app.
    final sync = ref.watch(syncProvider);
    final status = sync.isSyncing && sync.status.isNotEmpty
        ? sync.status
        : 'Restoring…';

    return PopScope(
      // Back must not dismiss it — the restore keeps running either way, and
      // leaving the user on a half-filled ledger is the failure this exists
      // to prevent.
      canPop: false,
      child: Dialog(
        backgroundColor: cs.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Restoring your data',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bringing back everything from your account. This can take a '
                'moment on the first run — please keep the app open.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 14),
              FieldLabel(status),
              const SizedBox(height: 6),
              Text(
                'Expenses · Debts · Categories · Settings',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
