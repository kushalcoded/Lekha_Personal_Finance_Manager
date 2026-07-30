import 'package:flutter/material.dart';

/// Navigation item model
class NavigationItem {
  final String id;
  final String label;
  final IconData icon;

  const NavigationItem({
    required this.id,
    required this.label,
    required this.icon,
  });
}

/// Bottom navigation tabs. Receivables + Payables live under Debts; History
/// folds into Insights; Settings is reached from the dashboard header.
enum NavigationTab { dashboard, expenses, insights, debts }

/// Extension to get navigation item details
extension NavigationTabExtension on NavigationTab {
  String get label {
    switch (this) {
      case NavigationTab.dashboard:
        return 'Home';
      case NavigationTab.expenses:
        return 'Expenses';
      case NavigationTab.insights:
        return 'Insights';
      case NavigationTab.debts:
        return 'Debts';
    }
  }

  IconData get icon {
    // Thin-line (outlined) set per the Midnight Terminal spec — nav is one
    // icon family; category icons keep Material Rounded.
    switch (this) {
      case NavigationTab.dashboard:
        return Icons.home_outlined;
      case NavigationTab.expenses:
        return Icons.receipt_long_outlined;
      case NavigationTab.insights:
        return Icons.insights_outlined;
      case NavigationTab.debts:
        return Icons.account_balance_wallet_outlined;
    }
  }

  String get id => name;

  NavigationItem toItem() => NavigationItem(id: id, label: label, icon: icon);

  static NavigationTab fromId(String id) {
    return NavigationTab.values.firstWhere(
      (tab) => tab.name == id,
      orElse: () => NavigationTab.dashboard,
    );
  }
}

/// List of all navigation items
final List<NavigationItem> navigationItems = [
  NavigationTab.dashboard,
  NavigationTab.expenses,
  NavigationTab.insights,
  NavigationTab.debts,
].map((tab) => tab.toItem()).toList();
