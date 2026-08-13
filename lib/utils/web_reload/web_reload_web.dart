import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get canReloadForUpdate => true;

/// Drop the cached PWA build and reload.
///
/// A plain refresh isn't enough: the service worker keeps serving the bundle it
/// already cached, so a freshly deployed version stays invisible — which looked
/// exactly like a feature failing to ship. Unregistering the worker and
/// clearing its caches forces the next load to come from the network.
Future<void> reloadForUpdate() async {
  try {
    final registrations = await web.window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    for (final registration in registrations.toDart) {
      await registration.unregister().toDart;
    }
  } catch (_) {
    // No service worker, or the browser refused — the reload below still
    // helps, so this must not stop it.
  }
  try {
    final keys = await web.window.caches.keys().toDart;
    for (final key in keys.toDart) {
      await web.window.caches.delete(key.toDart).toDart;
    }
  } catch (_) {
    // Cache Storage unavailable (private mode, older browser).
  }
  web.window.location.reload();
}
