/// Non-web builds have no service worker and nothing to reload.
bool get canReloadForUpdate => false;

Future<void> reloadForUpdate() async {}
