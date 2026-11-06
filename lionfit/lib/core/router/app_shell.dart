import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/profile/presentation/profile_screen.dart';
import '../../features/workout/presentation/rest_timer.dart';

/// One tab of the navigation bar.
final class ShellTab {
  const ShellTab({
    required this.label,
    required this.title,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;

  /// The app-bar title on the phone.
  final String title;
  final IconData icon;
  final IconData selectedIcon;
}

/// Same order as the shell's branches and `Routes.tabs`.
const kShellTabs = [
  ShellTab(
    label: 'Home',
    title: 'LionFit',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  ShellTab(
    label: 'History',
    title: 'Past workouts',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
  ),
  ShellTab(
    label: 'Log',
    title: "Today's workout",
    icon: Icons.fitness_center_outlined,
    selectedIcon: Icons.fitness_center,
  ),
  ShellTab(
    label: 'Muscle map',
    title: 'Muscle map',
    icon: Icons.accessibility_new_outlined,
    selectedIcon: Icons.accessibility_new,
  ),
  ShellTab(
    label: 'Profile',
    title: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
];

const _mapTab = 3;
const _profileTab = 4;

/// The signed-in frame around the five tabs.
///
/// * **Web**: a navigation bar across the top.
/// * **Android**: a bottom navigation bar, and the tabs swipe left/right.
///   Swiping is off on the muscle map, where a horizontal drag rotates the
///   3D model.
///
/// The rest timer sits just above the bottom bar (or at the bottom of the
/// page on web), so it keeps counting whichever tab is open.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.children,
    this.topNavigation = kIsWeb,
  });

  final StatefulNavigationShell navigationShell;

  /// One per tab, built by go_router.
  final List<Widget> children;

  /// Top bar (web) or bottom bar + swipe (app). Overridable for tests.
  final bool topNavigation;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final PageController _pages = PageController(
    initialPage: widget.navigationShell.currentIndex,
  );

  /// True while the page is moving because of a tap, not a swipe - the pages
  /// it passes through must not each become the current branch.
  bool _programmatic = false;

  int get _index => widget.navigationShell.currentIndex;

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pages.hasClients) return;
    final shown = _pages.page?.round();
    if (shown != _index) _showPage(_index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _showPage(int index) async {
    final from = _pages.page?.round() ?? index;
    // Jump on web, and across more than one tab: animating would build
    // every page in between (the 3D map included) just to slide past it.
    if (widget.topNavigation || (index - from).abs() > 1) {
      _pages.jumpToPage(index);
      return;
    }
    _programmatic = true;
    try {
      await _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _programmatic = false;
    }
  }

  void _select(int index) => widget.navigationShell.goBranch(
    index,
    // Tapping the current tab again returns it to its first screen.
    initialLocation: index == _index,
  );

  void _onPageChanged(int index) {
    if (_programmatic || index == _index) return;
    widget.navigationShell.goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.topNavigation;
    final swipe = !top && _index != _mapTab;
    final pages = PageView(
      controller: _pages,
      physics: swipe
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      onPageChanged: _onPageChanged,
      children: [for (final child in widget.children) _KeepAlive(child: child)],
    );

    if (top) {
      return Scaffold(
        appBar: _TopNavigationBar(selected: _index, onSelect: _select),
        body: pages,
        bottomNavigationBar: const RestTimerBar(whenExpanded: true),
      );
    }

    final tab = kShellTabs[_index];
    // The full-screen rest timer sits over everything, nav bar included.
    return Stack(
      children: [_appScaffold(tab, pages), const RestTimerOverlay()],
    );
  }

  Widget _appScaffold(ShellTab tab, Widget pages) {
    return Scaffold(
      appBar: AppBar(
        title: _index == 0 ? const _Brand() : Text(tab.title),
        actions: [
          if (_index == _profileTab) const ProfileMenuButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: pages,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RestTimerBar(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              for (final t in kShellTabs)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Keeps a tab's state (scroll position, an open form) when swiped away.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/android-chrome-192x192.png',
            width: 28,
            height: 28,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'LionFit',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        ),
      ],
    );
  }
}

/// The web header: brand on the left, the five tabs, and the profile menu
/// when the profile tab is open. Labels drop to icons on a narrow window.
class _TopNavigationBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopNavigationBar({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final showLabels = width >= 760;
    final showBrandName = width >= 520;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (showBrandName)
                const _Brand()
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/android-chrome-192x192.png',
                    width: 28,
                    height: 28,
                    semanticLabel: 'LionFit',
                  ),
                ),
              const Spacer(),
              for (var i = 0; i < kShellTabs.length; i++)
                _TopTab(
                  tab: kShellTabs[i],
                  selected: i == selected,
                  showLabel: showLabels,
                  onTap: () => onSelect(i),
                ),
              if (selected == _profileTab) ...[
                const SizedBox(width: 4),
                const ProfileMenuButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TopTab extends StatelessWidget {
  const _TopTab({
    required this.tab,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final ShellTab tab;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final icon = Icon(selected ? tab.selectedIcon : tab.icon, color: color);

    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      excludeSemantics: true,
      child: Tooltip(
        message: showLabel ? '' : tab.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 64,
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? scheme.secondary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (showLabel) ...[
                  const SizedBox(width: 8),
                  Text(
                    tab.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
