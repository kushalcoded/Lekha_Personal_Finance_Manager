import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../services/storage/hive_service.dart' show kLocalPrefsBox;
import 'navigation_models.dart';

/// Navigation state
class NavigationState {
  final NavigationTab currentTab;

  const NavigationState({this.currentTab = NavigationTab.dashboard});

  NavigationState copyWith({NavigationTab? currentTab}) {
    return NavigationState(currentTab: currentTab ?? this.currentTab);
  }
}

/// Navigation provider for managing current tab
final navigationProvider =
    StateNotifierProvider<NavigationNotifier, NavigationState>(
      (ref) => NavigationNotifier(),
    );

/// Navigation notifier for handling navigation changes
class NavigationNotifier extends StateNotifier<NavigationState> {
  NavigationNotifier() : super(NavigationState(currentTab: _restoreTab()));

  /// The tab from the last session, so a reload/restart resumes where the
  /// user left off. Box-open guard keeps widget tests (no Hive) working.
  static NavigationTab _restoreTab() {
    if (!Hive.isBoxOpen(kLocalPrefsBox)) return NavigationTab.dashboard;
    final id = Hive.box(kLocalPrefsBox).get('lastTab')?.toString() ?? '';
    return NavigationTabExtension.fromId(id);
  }

  /// Navigate to a specific tab
  void navigateTo(NavigationTab tab) {
    state = state.copyWith(currentTab: tab);
    if (Hive.isBoxOpen(kLocalPrefsBox)) {
      Hive.box(kLocalPrefsBox).put('lastTab', tab.name);
    }
  }

  /// Navigate using route string
  void navigateToRoute(String route) {
    final tab = NavigationTabExtension.fromId(route.replaceFirst('/', ''));
    navigateTo(tab);
  }

  /// Reset to default state
  void reset() {
    state = const NavigationState();
  }
}

/// Provider to get current navigation item
final currentNavigationItemProvider = Provider<NavigationItem>((ref) {
  final tab = ref.watch(navigationProvider).currentTab;
  return tab.toItem();
});

/// Provider to get all navigation items
final navigationItemsProvider = Provider<List<NavigationItem>>((ref) {
  return navigationItems;
});
