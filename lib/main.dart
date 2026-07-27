import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:home_widget/home_widget.dart';

import 'navigation/navigation.dart';
import 'screens/expenses/widgets/add_expense_modal.dart';
import 'widgets/common/ambient_background.dart';
import 'providers/onboarding/onboarding_provider.dart';
import 'providers/auth/auth_provider.dart';
import 'providers/sms/sms_providers.dart';
import 'providers/storage/storage_providers.dart';
import 'providers/sync/sync_providers.dart';
import 'screens/settings/providers/settings_providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/settings/widgets/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'services/storage/hive_service.dart';
import 'services/supabase/supabase_service.dart';

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
      await sync.forcePull();
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
      await hive.reassignUserData(localUserId, userId); // so pull's clear covers it
      await sync.forcePull();
    }
  } else if (localData) {
    // This account's own local data (or first-ever sign-in) → carry it up.
    await hive.reassignUserData(localUserId, userId);
    await sync.forcePush();
    _reloadStores(ref, userId);
  } else if (remote) {
    // Fresh device → pull the account down.
    await sync.forcePull();
  } else {
    _reloadStores(ref, userId);
  }
  await hive.setLocalDataOwner(userId);
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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingState = ref.watch(onboardingProvider);
    final authState = ref.watch(authStateProvider);

    // Reload the right data whenever auth flips. A *fresh* sign-in runs the
    // local-vs-cloud reconciler (handles conflicts + account switches); a
    // restored session just runs normal last-write-wins sync. Sign-out reloads
    // local data so offline use keeps showing everything.
    ref.listen(authStateProvider, (previous, next) {
      final was = previous?.isAuthenticated ?? false;
      if (next.isAuthenticated && !was) {
        final userId = next.userId;
        if (userId == null || userId.isEmpty) return;
        if (next.needsReconcile) {
          Future.microtask(() async {
            await reconcileSignIn(ref, userId);
            ref.read(authStateProvider.notifier).clearReconcileFlag();
          });
        } else {
          Future.microtask(() {
            _reloadStores(ref, userId);
            ref.read(syncProvider.notifier).autoSyncOnStartup();
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

    // Sign-in is optional. Show the prompt once after onboarding; skipping or
    // signing in dismisses it and the app opens offline-first thereafter.
    if (!authState.isAuthenticated && !ref.watch(authPromptDoneProvider)) {
      return LoginScreen(
        onFinished: () {
          HiveService().setAuthPromptShown();
          ref.read(authPromptDoneProvider.notifier).state = true;
        },
      );
    }

    return const _LocalDataBootstrap(child: AppShell());
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
  StreamSubscription<Uri?>? _widgetSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
    _widgetSub = HomeWidget.widgetClicked.listen(_openFromWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSms();
      _startPolling();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncSms();
      _startPolling();
    } else {
      _stopPolling();
      // Leaving the foreground: push the latest snapshot up so another device
      // gets this session's edits. push-only avoids clobbering them.
      if (ref.read(isAuthenticatedProvider)) {
        ref.read(syncProvider.notifier).syncNow(pushOnly: true);
      }
    }
  }

  /// While the app is in the foreground there's no lifecycle event when an SMS
  /// arrives, so poll the queue on a short timer for near-real-time detection.
  /// Idle polls are cheap — Gemini only runs when there's a new unseen debit.
  void _startPolling() {
    _smsPoll?.cancel();
    _smsPoll = Timer.periodic(const Duration(seconds: 5), (_) => _syncSms());
  }

  void _stopPolling() {
    _smsPoll?.cancel();
    _smsPoll = null;
  }

  /// Detect new bank/UPI debits from SMS captured while we were away.
  Future<void> _syncSms() async {
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
      }
      final count = await sms.sync();
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
