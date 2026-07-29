import 'package:web/web.dart' as web;

/// Remove OAuth params (`code`, `error`, …) from the browser URL after they've
/// been consumed. A single-use `?code=` left in the address bar breaks the
/// next reload: Supabase re-tries the dead code, the exchange fails, and the
/// stored session never gets restored — the "logged out on refresh" bug.
void stripAuthParamsFromUrl() {
  final uri = Uri.base;
  final params = uri.queryParameters;
  final hasAuthParams =
      params.containsKey('code') ||
      params.containsKey('error') ||
      params.containsKey('error_description') ||
      params.containsKey('access_token');
  if (!hasAuthParams) return;
  web.window.history.replaceState(null, '', uri.origin + uri.path);
}
