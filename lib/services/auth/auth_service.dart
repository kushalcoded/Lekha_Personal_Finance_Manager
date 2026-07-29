import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase/supabase_service.dart';

/// Authentication service for handling user authentication
/// Wraps Supabase Authentication
class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  late final SupabaseClient _supabase = SupabaseService.client;

  /// Emits on every Supabase auth change (initial restore, sign in, sign out,
  /// token refresh) — the single source of truth the notifier mirrors.
  Stream<AuthState> get onAuthChange => _supabase.auth.onAuthStateChange;

  /// OAuth deep-link this app is registered for (see AndroidManifest).
  /// NB: URL schemes can't contain underscores, so this is NOT the package id.
  static const _oauthRedirect = 'com.expanse.personaltracker://login-callback';

  /// Google sign-in via Supabase's OAuth browser flow. Returns once the
  /// browser is launched; the session arrives through [onAuthChange] when the
  /// redirect returns to the app. On web the redirect target is the page
  /// itself (same-tab), on Android the deep link above.
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      // Redirect back to this page (origin + path, no query/fragment).
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.origin + Uri.base.path,
      );
      return;
    }
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// Sign up user with email and password
  Future<AuthResponse> signup(String email, String password) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Login user with email and password
  Future<AuthResponse> login(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// Logout current user
  Future<void> logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      rethrow;
    }
  }

  /// Get current user ID
  String? getCurrentUserId() {
    return _supabase.auth.currentUser?.id;
  }

  /// Get current user email
  String? getCurrentUserEmail() {
    return _supabase.auth.currentUser?.email;
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      rethrow;
    }
  }

  /// Check if user is authenticated
  bool isAuthenticated() {
    return _supabase.auth.currentUser != null;
  }

  /// Restore session from stored token
  Future<bool> restoreSession() async {
    try {
      // Supabase automatically restores session from storage
      // If there's a valid session, it will be available
      return isAuthenticated();
    } catch (e) {
      return false;
    }
  }
}
