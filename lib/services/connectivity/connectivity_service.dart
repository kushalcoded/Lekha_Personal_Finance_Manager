import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Connectivity service for detecting online/offline state.
///
/// Probes the Supabase backend over HTTP instead of a dart:io DNS lookup so it
/// works on web too — and it's a truer "can I sync?" signal than generic DNS.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();

  factory ConnectivityService() {
    return _instance;
  }

  ConnectivityService._internal();

  /// Check if the sync backend is reachable. Any HTTP response (even 401)
  /// proves connectivity; only a network failure/timeout counts as offline.
  Future<bool> hasInternetConnection() async {
    final base = dotenv.env['SUPABASE_URL'];
    if (base == null || base.isEmpty) {
      // No backend configured — nothing to reach, don't block callers.
      return true;
    }
    try {
      final response = await http
          .get(Uri.parse('$base/auth/v1/health'))
          .timeout(const Duration(seconds: 6));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Quick check for connectivity (cached, not guaranteed)
  /// Use hasInternetConnection() for definitive check
  Future<bool> isOnline() async {
    return hasInternetConnection();
  }
}
