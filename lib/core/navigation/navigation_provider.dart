import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation_models.dart';

/// Navigation state
class NavigationState {
  final NavigationTab currentTab;

  const NavigationState({
    this.currentTab = NavigationTab.dashboard,
  });

  NavigationState copyWith({
    NavigationTab? currentTab,
  }) {
    return NavigationState(
      currentTab: currentTab ?? this.currentTab,
    );
  }
}

/// Navigation provider for managing current tab
final navigationProvider =
    StateNotifierProvider<NavigationNotifier, NavigationState>(
      (ref) => NavigationNotifier(),
    );

/// Navigation notifier for handling navigation changes
class NavigationNotifier extends StateNotifier<NavigationState> {
  NavigationNotifier() : super(const NavigationState());

  /// Navigate to a specific tab
  void navigateTo(NavigationTab tab) {
    state = state.copyWith(currentTab: tab);
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
