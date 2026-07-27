import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/navigation_provider.dart';
import '../providers/categories/category_providers.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/expenses/expenses_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/debts/debts_screen.dart';
import 'floating_glass_nav.dart';

/// App shell: the current tab under a floating glass navigation bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationState = ref.watch(navigationProvider);
    // Load custom categories once so their icons/colors apply app-wide.
    ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Content fills the screen and scrolls *under* the frosted nav;
          // each screen adds kNavBottomInset padding so nothing hides.
          Positioned.fill(
            child: _buildScreenContent(navigationState.currentTab),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: FloatingGlassNav(),
          ),
        ],
      ),
    );
  }

  /// Build screen content based on current tab
  Widget _buildScreenContent(NavigationTab currentTab) {
    switch (currentTab) {
      case NavigationTab.dashboard:
        return const DashboardScreen();
      case NavigationTab.expenses:
        return const ExpensesScreen();
      case NavigationTab.insights:
        return const AnalyticsScreen();
      case NavigationTab.debts:
        return const DebtsScreen();
    }
  }
}
