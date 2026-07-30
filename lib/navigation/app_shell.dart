import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/navigation_provider.dart';
import '../providers/categories/category_providers.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/expenses/expenses_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/debts/debts_screen.dart';
import '../screens/expenses/widgets/add_expense_modal.dart';
import '../screens/expenses/widgets/expenses_widgets.dart'
    show ExpenseSearchBar;
import 'floating_glass_nav.dart';

/// App shell: the current tab under a floating glass navigation bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  /// True while a text field owns focus — keyboard shortcuts must not fire
  /// when the user is typing an amount or note.
  static bool _typing() {
    final focus = FocusManager.instance.primaryFocus;
    return focus?.context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationState = ref.watch(navigationProvider);
    // Load custom categories once so their icons/colors apply app-wide.
    ref.watch(categoriesProvider);

    // Layout answers to window width, not device type: wide (desktop web,
    // tablets landscape) gets a left rail; narrow keeps the bottom nav.
    final isWide = MediaQuery.sizeOf(context).width >= kWideBreakpoint;

    if (isWide) {
      void goTo(NavigationTab tab) {
        if (_typing()) return;
        ref.read(navigationProvider.notifier).navigateTo(tab);
      }

      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN): () {
            if (!_typing()) showAddExpenseModal(context);
          },
          const SingleActivator(LogicalKeyboardKey.digit1): () =>
              goTo(NavigationTab.dashboard),
          const SingleActivator(LogicalKeyboardKey.digit2): () =>
              goTo(NavigationTab.expenses),
          const SingleActivator(LogicalKeyboardKey.digit3): () =>
              goTo(NavigationTab.insights),
          const SingleActivator(LogicalKeyboardKey.digit4): () =>
              goTo(NavigationTab.debts),
          // "/" jumps to Expenses and drops the cursor into search.
          const SingleActivator(LogicalKeyboardKey.slash): () {
            if (_typing()) return;
            ref
                .read(navigationProvider.notifier)
                .navigateTo(NavigationTab.expenses);
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => ExpenseSearchBar.focusNode.requestFocus(),
            );
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FloatingGlassRail(),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: _buildScreenContent(navigationState.currentTab),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
