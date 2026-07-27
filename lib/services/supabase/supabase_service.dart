import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase service - initializes and manages Supabase client
class SupabaseService {
  static late final Supabase _instance;

  static SupabaseClient get client => _instance.client;

  /// Initialize Supabase from .env configuration
  static Future<void> initialize() async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'];
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (supabaseUrl == null || supabaseAnonKey == null) {
      throw Exception(
        'Missing Supabase configuration. Ensure .env file contains '
        'SUPABASE_URL and SUPABASE_ANON_KEY',
      );
    }

    _instance = await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  /// Test Supabase connection by performing a lightweight query
  /// Returns success message or throws exception with failure reason
  static Future<String> testConnection() async {
    try {
      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

      if (supabaseUrl == null || supabaseAnonKey == null) {
        throw 'Missing Supabase configuration';
      }

      final response = await http.get(
        Uri.parse('$supabaseUrl/rest/v1/'),
        headers: {
          'apikey': supabaseAnonKey,
          'Authorization': 'Bearer $supabaseAnonKey',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode >= 500) {
        throw 'Supabase responded with HTTP ${response.statusCode}';
      }

      return 'Connection successful! Supabase is reachable.';
    } catch (e) {
      throw 'Connection failed: ${e.toString()}';
    }
  }
}
