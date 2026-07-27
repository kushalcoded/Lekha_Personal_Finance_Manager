import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/navigation_provider.dart';
import '../screens/expenses/widgets/add_expense_modal.dart';

/// Bottom padding a tab screen's scrollable should add so its last content
/// clears the floating navigation bar (pill + margin + safe area headroom).
const double kNavBottomInset = 120;

/// Floating, frosted-glass bottom bar: two tabs, a raised center Add button,
/// two tabs. Detached from the screen edges with a soft shadow.
class FloatingGlassNav extends ConsumerWidget {
  const FloatingGlassNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(navigationProvider).currentTab;
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 12 + bottomInset),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Glass pill
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40,
                  spreadRadius: -8,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      _tab(ref, navigationItems[0], currentTab),
                      _tab(ref, navigationItems[1], currentTab),
                      const SizedBox(width: 72),
                      _tab(ref, navigationItems[2], currentTab),
                      _tab(ref, navigationItems[3], currentTab),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Circular Add button, seated into the pill's center with a small
          // lift — a circle overlaps the bar cleanly where a square didn't.
          Positioned(
            top: -12,
            child: _AddButton(onTap: () => showAddExpenseModal(context)),
          ),
        ],
      ),
    );
  }

  Widget _tab(WidgetRef ref, NavigationItem item, NavigationTab current) {
    return Expanded(
      child: _NavButton(
        item: item,
        isActive: current.id == item.id,
        onTap: () => ref
            .read(navigationProvider.notifier)
            .navigateTo(NavigationTabExtension.fromId(item.id)),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final NavigationItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isActive
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return InkResponse(
      onTap: onTap,
      radius: 34,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 23, color: color),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B7CF6), Color(0xFF6E5CE6)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.5),
            blurRadius: 26,
            spreadRadius: -2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(
            Icons.add_rounded,
            color: colorScheme.onPrimary,
            size: 32,
          ),
        ),
      ),
    );
  }
}
