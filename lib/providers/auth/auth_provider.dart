import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../services/auth/auth_service.dart';
import '../../services/storage/hive_service.dart';
import '../../services/sync/supabase_sync_service.dart';
import '../../utils/url_cleanup/url_cleanup_stub.dart'
    if (dart.library.js_interop) '../../utils/url_cleanup/url_cleanup_web.dart';

const localUserId = 'local_android_user';
const localUserEmail = 'Local Android User';

/// State class for authentication
class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? userId;
  final String? userEmail;
  final String? errorMessage;

  /// True right after an explicit sign-in (not a restored session), signalling
  /// the app to run the local-vs-cloud reconciliation once.
  final bool needsReconcile;

  /// True once the startup session-restore check has answered (either way).
  /// Until then the app shows a loader instead of flashing the login screen.
  final bool resolved;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.userId,
    this.userEmail,
    this.errorMessage,
    this.needsReconcile = false,
    this.resolved = false,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? userId,
    String? userEmail,
    String? errorMessage,
    bool? needsReconcile,
    bool? resolved,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      errorMessage: errorMessage,
      needsReconcile: needsReconcile ?? this.needsReconcile,
      resolved: resolved ?? this.resolved,
    );
  }
}

/// Riverpod provider for authentication state
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService = AuthService();
  StreamSubscription<sb.AuthState>? _sub;

  AuthNotifier() : super(const AuthState()) {
    // Supabase's stream is the source of truth: it emits the restored session
    // on startup and every subsequent sign-in/out (incl. Google OAuth, whose
    // session only arrives after the redirect deep-link).
    try {
      _sub = _authService.onAuthChange.listen(_onAuthChange);
      // Belt & braces: if no initial event lands (shouldn't happen), don't
      // leave the app stuck on the boot loader.
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !state.resolved) {
          state = state.copyWith(resolved: true);
        }
      });
    } catch (_) {
      // Supabase unavailable (offline/unconfigured) — resolve as signed out
      // so the login screen renders instead of an infinite loader.
      state = const AuthState(resolved: true);
    }
  }

  void _onAuthChange(sb.AuthState data) {
    final session = data.session;
    if (data.event == sb.AuthChangeEvent.signedOut || session == null) {
      state = const AuthState(resolved: true);
      return;
    }
    // Web: the OAuth ?code= in the URL is consumed now — scrub it so a later
    // reload doesn't re-try the dead code and lose the session.
    stripAuthParamsFromUrl();
    // Only an explicit sign-in needs the one-time local-vs-cloud reconcile; a
    // restored session (app relaunch) just runs normal last-write-wins sync.
    final fresh = data.event == sb.AuthChangeEvent.signedIn;
    state = AuthState(
      isAuthenticated: true,
      userId: session.user.id,
      userEmail: session.user.email,
      needsReconcile: fresh,
      resolved: true,
    );
  }

  void clearReconcileFlag() {
    if (state.needsReconcile) {
      state = state.copyWith(needsReconcile: false);
    }
  }

  /// Login user with email and password. State flips via [_onAuthChange].
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authService.login(email, password);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Sign up with email and password, then auto-login.
  Future<bool> signup(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authService.signup(email, password);
      await _authService.login(email, password);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Google sign-in via Supabase OAuth. The session lands through
  /// [_onAuthChange] once the browser redirect returns to the app.
  Future<bool> loginWithGoogle() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authService.signInWithGoogle();
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Logout current user and keep everything usable offline. First push the
  /// latest snapshot up (so this account's data is safe in its own cloud before
  /// any account switch), then re-key the data back to the local id so it stays
  /// visible in local mode, tagging which account it belongs to.
  Future<void> logout() async {
    final userId = state.userId;
    state = state.copyWith(isLoading: true);
    try {
      if (userId != null && userId.isNotEmpty) {
        try {
          await SupabaseSyncService().syncUser(userId, pushOnly: true);
        } catch (_) {
          // Offline logout: local data is still preserved below.
        }
        final hive = HiveService();
        await hive.reassignUserData(userId, localUserId);
        await hive.setLocalDataOwner(userId);
      }
      await _authService.logout();
      state = const AuthState(resolved: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Reset password for email
  Future<bool> resetPassword(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authService.resetPassword(email);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }
}

/// Derived provider to check if user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isAuthenticated;
});

/// Derived provider to get current user ID
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  if (authState.isAuthenticated &&
      authState.userId != null &&
      authState.userId!.isNotEmpty) {
    return authState.userId;
  }
  return localUserId;
});

/// Derived provider to get current user email
final currentUserEmailProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  if (authState.isAuthenticated &&
      authState.userEmail != null &&
      authState.userEmail!.isNotEmpty) {
    return authState.userEmail;
  }
  return localUserEmail;
});
