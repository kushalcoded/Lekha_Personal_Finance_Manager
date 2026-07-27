import 'dart:io';

/// Connectivity service for detecting online/offline state
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();

  factory ConnectivityService() {
    return _instance;
  }

  ConnectivityService._internal();

  /// Check if device has internet connection
  /// Uses a simple DNS lookup to detect connectivity
  Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('dns.google');
      // If we get any result, we have internet
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
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
