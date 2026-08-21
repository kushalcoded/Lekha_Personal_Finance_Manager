import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';

import 'navigation/navigation.dart';
import 'screens/expenses/widgets/add_expense_modal.dart';
import 'widgets/common/ambient_background.dart';
import 'providers/onboarding/onboarding_provider.dart';
import 'providers/auth/auth_provider.dart';
import 'providers/share/share_providers.dart';
import 'providers/sms/sms_providers.dart';
import 'providers/storage/storage_providers.dart';
import 'providers/sync/sync_providers.dart';
import 'screens/settings/providers/settings_providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/onboarding/first_run_sheet.dart';
import 'screens/onboarding/restoring_screen.dart';
import 'screens/settings/widgets/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'screens/settings/providers/reminder_providers.dart';
import 'services/errors/error_reporter.dart';
import 'services/notifications/reminder_notifications.dart';
import 'services/storage/hive_service.dart';
import 'services/supabase/supabase_service.dart';
import 'utils/url_cleanup/url_cleanup_stub.dart'
    if (dart.library.js_interop) 'utils/url_cleanup/url_cleanup_web.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load();

  // Initialize Hive for offline-first storage
  await HiveService.initialize();

  // Initialize Supabase (safe if config missing - app still works offline)
  try {
    await SupabaseService.initialize();
  } catch (e) {
    debugPrint('⚠️ Supabase initialization failed: $e');
    debugPrint('App will run in offline-only mode');
  }
  // Web: drop consumed OAuth params from the URL so a reload doesn't re-try a
  // dead ?code= and wreck session restore ("logged out on refresh").
  stripAuthParamsFromUrl();

  // After Supabase, since a report needs its client. Settings flips this off
  // again once they load, if that's what the user chose.
  await ErrorReporter.install();

  runApp(const ProviderScope(child: MyApp()));
}

/// Lets the home-screen widget open the add-expense sheet over the app.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Refetch every money store for [userId] (real account id, or [localUserId]
/// after a logout) so the UI reflects the currently-scoped data.
void _reloadStores(WidgetRef ref, String userId) {
  ref.read(expensesProvider.notifier).fetchExpenses(userId);
  ref.read(receivablesProvider.notifier).fetchReceivables(userId);
  ref.read(payablesProvider.notifier).fetchPayables(userId);
  ref.read(recurringTemplatesProvider.notifier).fetchTemplates(userId);
}

/// Runs once after an explicit sign-in to reconcile this device's local data
/// with the account's cloud snapshot. Handles three cases safely:
///  - different account's data on this device → don't merge; load this account.
///  - offline data + existing cloud data (ambiguous) → ask the user.
///  - otherwise → carry local up, or pull cloud down.
Future<void> reconcileSignIn(WidgetRef ref, String userId) async {
  final hive = HiveService();
  final sync = ref.read(syncProvider.notifier);
  final localData = hive.hasDataFor(localUserId);
  final owner = hive.getLocalDataOwner();
  final remote = await sync.hasRemote();

  if (localData && owner.isNotEmpty && owner != userId) {
    // Different account's data sits on this device (it's safe in its own cloud,
    // pushed on logout). Load THIS account instead of merging.
    if (remote) {
      await _showingRestore(() => sync.forcePull());
    } else {
      await hive.clearAllData();
      _reloadStores(ref, userId);
    }
  } else if (localData && remote && owner.isEmpty) {
    // Pure-offline data AND this account already has a cloud copy → ambiguous.
    final keepDevice = await _askKeepWhich();
    if (keepDevice == null) {
      await ref.read(authStateProvider.notifier).logout(); // cancelled
      return;
    }
    if (keepDevice) {
      await hive.reassignUserData(localUserId, userId);
      await sync.forcePush();
      _reloadStores(ref, userId);
    } else {
      await hive.reassignUserData(
        localUserId,
        userId,
      ); // so pull's clear covers it
      await _showingRestore(() => sync.forcePull());
    }
  } else if (localData) {
    // This account's own local data (or first-ever sign-in) → carry it up.
    await hive.reassignUserData(localUserId, userId);
    await sync.forcePush();
    _reloadStores(ref, userId);
  } else if (remote) {
    // Fresh device → pull the account down. The long one, and the one people
    // hit right after installing, so it gets the blocking screen.
    await _showingRestore(() => sync.forcePull());
  } else {
    _reloadStores(ref, userId);
  }
  await hive.setLocalDataOwner(userId);
}

/// Run [work] behind the blocking restore screen.
///
/// The dialog's own context is captured rather than popping the navigator
/// blind: this runs from a microtask at sign-in, when the display-name prompt
/// and the first-run sheet are queued right behind it, and popping "whatever
/// is on top" would eventually close one of those instead.
///
/// If there is no UI yet the work still runs — the restore matters more than
/// the screen describing it.
Future<void> _showingRestore(Future<void> Function() work) async {
  final context = navigatorKey.currentContext;
  if (context == null) return work();

  BuildContext? dialogContext;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const RestoringDialog();
      },
    ),
  );
  try {
    await work();
  } finally {
    // In a finally: a restore that throws must not leave a modal with no
    // buttons sitting over the app forever.
    final ctx = dialogContext;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
  }
}

/// Conflict prompt: true = keep this device, false = keep cloud, null = cancel.
Future<bool?> _askKeepWhich() async {
  final context = navigatorKey.currentContext;
  if (context == null) return true; // no UI available → safest is keep device
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Merge your data'),
      content: const Text(
        'This device has data added while signed out, and your account already '
        'has data in the cloud. They can\'t be merged automatically — which do '
        'you want to keep?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep cloud'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Keep this device'),
        ),
      ],
    ),
  );
}

/// Tell the user their sign-in merge did not go through.
///
/// Deliberately loud and non-dismissible-by-accident: everything else in this
/// app fails quiet and retries, but this one decides which copy of their data
/// wins, and getting it wrong is unrecoverable.
void _showReconcileFailed(Object error) {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Could not finish setting up'),
      content: Text(
        'Your data is safe on this device, but it has not been merged with '
        'the cloud yet. Check your connection and sign in again.\n\n$error',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// First sign-in on this account: ask for the handful of things that decide
/// what the dashboard can even show. Anything skipped resurfaces on the
/// dashboard checklist rather than hiding in Settings.
Future<void> _maybeRunFirstRun(String userId) async {
  if (firstRunDone(userId)) return;
  final context = navigatorKey.currentContext;
  if (context == null) return;
  await showFirstRunSheet(context, userId);
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingState = ref.watch(onboardingProvider);
    final authState = ref.watch(authStateProvider);

    // Reload the right data whenever auth flips. A *fresh* sign-in runs the
    // local-vs-cloud reconciler (handles conflicts + account switches); a
    // restored session just runs normal last-write-wins sync. Sign-out reloads
    // local data so nothing is lost while signed out.
    ref.listen(authStateProvider, (previous, next) {
      final was = previous?.isAuthenticated ?? false;
      if (next.isAuthenticated && !was) {
        final userId = next.userId;
        if (userId == null || userId.isEmpty) return;
        if (next.needsReconcile) {
          Future.microtask(() async {
            // Guarded, and the flag is only cleared on success. This is the one
            // place a silent failure loses data: the user picks "Keep this
            // device", forcePush throws, and without this they are told nothing
            // while believing their offline data reached the cloud. Leaving
            // needsReconcile set means the next sign-in asks again instead of
            // quietly moving on.
            try {
              await reconcileSignIn(ref, userId);
              ref.read(authStateProvider.notifier).clearReconcileFlag();
            } catch (e) {
              _showReconcileFailed(e);
              return;
            }
            await _maybeAskDisplayName(ref, userId);
            await _maybeRunFirstRun(userId);
          });
        } else {
          Future.microtask(() async {
            _reloadStores(ref, userId);
            ref.read(syncProvider.notifier).autoSyncOnStartup();
            await _maybeAskDisplayName(ref, userId);
            await _maybeRunFirstRun(userId);
          });
        }
      } else if (!next.isAuthenticated && was) {
        Future.microtask(() => _reloadStores(ref, localUserId));
      }
    });

    return MaterialApp(
      title: 'Lekha',
      navigatorKey: navigatorKey,
      theme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      builder: (context, child) =>
          AmbientBackground(child: child ?? const SizedBox.shrink()),
      home: _SplashGate(child: _buildHome(ref, onboardingState, authState)),
      debugShowCheckedModeBanner: false,
    );
  }

  Widget _buildHome(
    WidgetRef ref,
    OnboardingState onboardingState,
    AuthState authState,
  ) {
    // Show loading while checking onboarding status
    if (onboardingState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If onboarding not completed, show onboarding
    if (!onboardingState.isCompleted) {
      return const OnboardingScreen();
    }

    // Sign-in is required. Hold on a loader until the restored-session check
    // finishes so the login screen doesn't flash on every launch.
    if (!authState.isAuthenticated) {
      if (!authState.resolved) {
        return const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return const LoginScreen();
    }

    return const _LocalDataBootstrap(child: AppShell());
  }
}

/// One-time after sign-in: if no display name is stored yet, ask for one —
/// prefilled from the Google profile (or the email prefix).
Future<void> _maybeAskDisplayName(WidgetRef ref, String userId) async {
  final hive = HiveService();
  final existing = (hive.getSettings(userId)['displayName'] as String?) ?? '';
  if (existing.trim().isNotEmpty) return;

  String suggestion = '';
  try {
    final user = SupabaseService.client.auth.currentUser;
    suggestion =
        (user?.userMetadata?['full_name'] ??
                user?.userMetadata?['name'] ??
                user?.email?.split('@').first ??
                '')
            .toString();
  } catch (_) {}

  final context = navigatorKey.currentContext;
  if (context == null) return;
  final ctrl = TextEditingController(text: suggestion);
  final name = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('What should we call you?'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Your name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) {
    // Merge-write directly so a still-loading settings provider can't clobber
    // other settings, then refresh the provider.
    await hive.updateSetting(userId, 'displayName', name);
    await ref.read(settingsProvider.notifier).loadSettings();
  }
}

/// Plays the opening animation once per cold start, then cross-fades to [child].
class _SplashGate extends StatefulWidget {
  final Widget child;

  const _SplashGate({required this.child});

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: _done
          ? widget.child
          : SplashScreen(
              key: const ValueKey('splash'),
              onDone: () {
                if (mounted) setState(() => _done = true);
              },
            ),
    );
  }
}

class _LocalDataBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const _LocalDataBootstrap({required this.child});

  @override
  ConsumerState<_LocalDataBootstrap> createState() =>
      _LocalDataBootstrapState();
}

class _LocalDataBootstrapState extends ConsumerState<_LocalDataBootstrap>
    with WidgetsBindingObserver {
  bool _loaded = false;
  bool _smsPermissionAsked = false;
  bool _syncing = false;
  Timer? _smsPoll;
  Timer? _sharePoll;
  Timer? _pushDebounce;
  StreamSubscription<Uri?>? _widgetSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Home-screen widget is Android-only; its channel throws on web.
    if (!kIsWeb) {
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
      _widgetSub = HomeWidget.widgetClicked.listen(_openFromWidget);
    }
    // Near-real-time cloud copy: any data mutation schedules a debounced push
    // (~10s after the last edit), so other devices see changes without
    // waiting for this one to be backgrounded.
    HiveService.onDataChanged = _schedulePush;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSms(force: true);
      _syncShare();
      _startPolling();
      _rescheduleReminder();
    });
  }

  void _schedulePush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (ref.read(isAuthenticatedProvider)) {
        ref.read(syncProvider.notifier).syncNow(pushOnly: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back is exactly when the cloud queue is worth a look, so skip
      // the throttle here; the periodic poll keeps to it.
      _syncSms(force: true);
      _syncShare();
      _startPolling();
      _rescheduleReminder();
    } else {
      // Last chance to leave an accurate nudge behind: the notification text
      // is a snapshot, and this is the moment the data is freshest.
      _rescheduleReminder();
      _stopPolling();
      // Leaving the foreground: push the latest snapshot up so another device
      // gets this session's edits. push-only avoids clobbering them.
      if (ref.read(isAuthenticatedProvider)) {
        ref.read(syncProvider.notifier).syncNow(pushOnly: true);
      }
    }
  }

  /// Rebuild the daily reminder from what the app knows right now. Cheap, and
  /// the only thing keeping the notification's wording honest — nothing runs in
  /// the background to refresh it.
  Future<void> _rescheduleReminder() async {
    if (!ReminderNotifications.supported) return;
    if (!ref.read(settingsProvider).remindersEnabled) {
      await ReminderNotifications.cancel();
      return;
    }
    final digest = reminderDigest(ref.read(upcomingRemindersProvider));
    if (digest == null) {
      await ReminderNotifications.cancel();
      return;
    }
    await ReminderNotifications.scheduleDaily(
      title: digest.title,
      body: digest.body,
    );
  }

  /// While the app is in the foreground there's no lifecycle event when an SMS
  /// arrives, so poll the queue on a short timer for near-real-time detection.
  /// Idle polls are cheap — Gemini only runs when there's a new unseen debit.
  void _startPolling() {
    _smsPoll?.cancel();
    _smsPoll = Timer.periodic(const Duration(seconds: 5), (_) => _syncSms());
    // A sibling timer rather than a second job on the 5s tick: SmsCaptureService
    // already re-throttles its own network half to 60s internally, so hanging
    // this off that tick would mean writing a second throttle inside a timer
    // that exists to be throttled. A friend's entry arriving within a minute is
    // fine; the ledger screen also refreshes the moment it is opened.
    _sharePoll?.cancel();
    _sharePoll = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _syncShare(),
    );
  }

  void _stopPolling() {
    _smsPoll?.cancel();
    _smsPoll = null;
    _sharePoll?.cancel();
    _sharePoll = null;
  }

  /// Pull anything guests did on their shared pages. Silent on failure, like
  /// every other network path here.
  Future<void> _syncShare() {
    return ref.read(sharedInboxProvider.notifier).refresh();
  }

  /// Detect new bank/UPI debits from SMS captured while we were away.
  Future<void> _syncSms({bool force = false}) async {
    if (_syncing) return;
    if (!ref.read(settingsProvider).smsAutoDetectEnabled) return;
    _syncing = true;
    try {
      final sms = ref.read(smsCaptureServiceProvider);
      if (!_smsPermissionAsked) {
        _smsPermissionAsked = true;
        if (!await sms.hasPermission()) {
          await sms.requestPermission();
        }
        // Hive holds the toggle but the SMS receiver can only read
        // SharedPreferences, so re-assert it — a reinstall or a restored
        // backup leaves the native side at its default.
        await sms.setNotify(ref.read(settingsProvider).smsNotifyEnabled);
      }
      final count = await sms.sync(force: force);
      if (count > 0 && mounted) {
        ref.read(pendingTransactionsProvider.notifier).refresh();
      }
    } finally {
      _syncing = false;
    }
  }

  void _openFromWidget(Uri? uri) {
    if (uri == null) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showAddExpenseModal(ctx, autoStartVoice: uri.host == 'voice');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _pushDebounce?.cancel();
    HiveService.onDataChanged = null;
    _widgetSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    Future.microtask(() async {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null || userId.isEmpty) return;
      await Future.wait([
        ref.read(expensesProvider.notifier).fetchExpenses(userId),
        ref.read(receivablesProvider.notifier).fetchReceivables(userId),
        ref.read(payablesProvider.notifier).fetchPayables(userId),
        ref.read(recurringTemplatesProvider.notifier).fetchTemplates(userId),
      ]);
      await ref.read(syncProvider.notifier).refreshStatus();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
