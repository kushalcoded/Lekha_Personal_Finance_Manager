import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/navigation_provider.dart';
import '../providers/sync/sync_providers.dart';
import '../services/storage/hive_service.dart' show kLocalPrefsBox;
import '../screens/expenses/widgets/add_expense_modal.dart';
import '../screens/settings/providers/settings_providers.dart';
import '../screens/settings/settings_screen.dart';
import '../utils/formatters/formatters.dart';

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
              color: const Color(0xFF131318),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
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

/// Desktop counterpart of [FloatingGlassNav]. 900–1280px: a compact icon
/// rail. ≥1280px: a labeled sidebar (collapsible back down to the icon rail;
/// the choice sticks per device, like the last-open tab).
class FloatingGlassRail extends ConsumerStatefulWidget {
  const FloatingGlassRail({super.key});

  @override
  ConsumerState<FloatingGlassRail> createState() => _FloatingGlassRailState();
}

class _FloatingGlassRailState extends ConsumerState<FloatingGlassRail> {
  bool _collapsed =
      Hive.isBoxOpen(kLocalPrefsBox) &&
      Hive.box(kLocalPrefsBox).get('sidebarCollapsed') == true;

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    if (Hive.isBoxOpen(kLocalPrefsBox)) {
      Hive.box(kLocalPrefsBox).put('sidebarCollapsed', _collapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(navigationProvider).currentTab;
    // Below 1280px there isn't room for the labeled sidebar, so the compact
    // rail is forced and the expand toggle hidden.
    final canExpand = MediaQuery.sizeOf(context).width >= 1280;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.centerLeft,
      child: canExpand && !_collapsed
          ? _LabeledSidebar(currentTab: currentTab, onCollapse: _toggle)
          : _CompactRail(
              currentTab: currentTab,
              onExpand: canExpand ? _toggle : null,
            ),
    );
  }
}

/// Icon-only rail: always at 900–1280px, and the collapsed state ≥1280px.
class _CompactRail extends ConsumerWidget {
  final NavigationTab currentTab;
  final VoidCallback? onExpand;

  const _CompactRail({required this.currentTab, this.onExpand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      child: Container(
        width: 84,
        decoration: BoxDecoration(
          color: const Color(0xFF131318),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
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
            if (onExpand != null) ...[
              const SizedBox(height: 6),
              IconButton(
                tooltip: 'Expand sidebar',
                iconSize: 20,
                icon: Icon(
                  Icons.keyboard_double_arrow_right_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                onPressed: onExpand,
              ),
              const SizedBox(height: 4),
            ] else
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

/// ≥1280px sidebar: labeled tabs, a real New-expense button (with its "N"
/// keyboard hint), and sync + account status where the eye rests.
class _LabeledSidebar extends ConsumerWidget {
  final NavigationTab currentTab;
  final VoidCallback onCollapse;

  const _LabeledSidebar({required this.currentTab, required this.onCollapse});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final sync = ref.watch(syncProvider);
    final name = ref.watch(settingsProvider.select((s) => s.displayName));

    final syncLabel = sync.isSyncing
        ? 'Syncing…'
        : sync.lastSyncedAt == null
        ? 'Not synced yet'
        : 'Synced ${AppFormatters.getRelativeTime(sync.lastSyncedAt!)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: const Color(0xFF131318),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: cs.primary,
                    ),
                    child: Text(
                      '₹',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Lekha',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: 'Space Grotesk',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Collapse sidebar',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    iconSize: 18,
                    icon: Icon(
                      Icons.keyboard_double_arrow_left_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: onCollapse,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final item in navigationItems)
              _SidebarItem(
                item: item,
                isActive: currentTab.id == item.id,
                onTap: () => ref
                    .read(navigationProvider.notifier)
                    .navigateTo(NavigationTabExtension.fromId(item.id)),
              ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => showAddExpenseModal(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('+ New expense'),
                  const SizedBox(width: 8),
                  Opacity(
                    opacity: 0.55,
                    child: Text(
                      'N',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  // Green only when the data really is up in the cloud.
                  Icon(
                    Icons.circle,
                    size: 7,
                    color: sync.isSyncing
                        ? const Color(0xFFF0A13B)
                        : sync.lastSyncedAt == null
                        ? cs.onSurfaceVariant
                        : const Color(0xFF46C98B),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      syncLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: const Color(0xFF1A1A21),
                      child: Text(
                        name.isEmpty ? '₹' : name[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Account' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Icon(
                      Icons.settings_outlined,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final NavigationItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isActive ? cs.onSurface : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? cs.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 20, color: color),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 15,
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
