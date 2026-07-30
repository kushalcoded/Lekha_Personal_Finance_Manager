import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/navigation_provider.dart';
import '../screens/expenses/widgets/add_expense_modal.dart';
import '../screens/settings/settings_screen.dart';

/// Bottom padding a tab screen's scrollable should add so its last content
/// clears the floating navigation bar (bar + margin + safe area headroom).
const double kNavBottomInset = 120;

/// Window width at/above which the app switches to the desktop layout
/// (left rail, grids, master-detail). Same breakpoint as responsive sheets.
const double kWideBreakpoint = 900;

/// Bottom bar: two tabs, a raised center Add button, two tabs. Solid surface,
/// hairline border, active-tab pill — floated off the edges so the reachable
/// thumb zone stays the same.
class FloatingGlassNav extends ConsumerWidget {
  const FloatingGlassNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(navigationProvider).currentTab;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 12 + bottomInset),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: double.infinity,
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFF1C1925),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 28,
                  spreadRadius: -10,
                  offset: const Offset(0, 12),
                ),
              ],
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
          // Circular Add button, seated into the bar's center with a small
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

/// Desktop counterpart of [FloatingGlassNav]: a left rail — logo, the four
/// tabs, the Add button, and Settings — so nav and primary actions stay
/// within reach of the cursor on wide screens.
class FloatingGlassRail extends ConsumerWidget {
  const FloatingGlassRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(navigationProvider).currentTab;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      child: Container(
        width: 84,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1925),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.primary,
              ),
              child: Text(
                '₹',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 18),
            for (final item in navigationItems)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: 54,
                  child: _NavButton(
                    item: item,
                    isActive: currentTab.id == item.id,
                    onTap: () => ref
                        .read(navigationProvider.notifier)
                        .navigateTo(NavigationTabExtension.fromId(item.id)),
                  ),
                ),
              ),
            const Spacer(),
            Transform.scale(
              scale: 0.78,
              child: _AddButton(onTap: () => showAddExpenseModal(context)),
            ),
            const SizedBox(height: 10),
            IconButton(
              tooltip: 'Settings',
              icon: Icon(
                Icons.settings_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
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
    final color = isActive ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return InkResponse(
      onTap: onTap,
      radius: 34,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
        ),
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
        color: colorScheme.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 16,
            spreadRadius: -4,
            offset: const Offset(0, 6),
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
