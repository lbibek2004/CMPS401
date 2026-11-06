import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lionfit/core/router/app_shell.dart';
import 'package:lionfit/core/router/routes.dart';
import 'package:lionfit/core/theme/app_theme.dart';
import 'package:lionfit/features/workout/presentation/rest_timer.dart';

/// The navigation frame with stand-in tabs: bottom bar + swipe on the app,
/// a top bar on the web, the profile hamburger, and the rest timer strip.
void main() {
  GoRouter routerFor({required bool top}) => GoRouter(
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute(
        builder: (_, _, shell) => shell,
        navigatorContainerBuilder: (context, shell, children) => AppShell(
          navigationShell: shell,
          topNavigation: top,
          children: children,
        ),
        branches: [
          for (final path in Routes.tabs)
            StatefulShellBranch(
              preload: true,
              routes: [
                GoRoute(
                  path: path,
                  builder: (_, _) =>
                      Scaffold(body: Center(child: Text('page $path'))),
                ),
              ],
            ),
        ],
      ),
    ],
  );

  Future<GoRouter> pumpShell(
    WidgetTester tester, {
    required bool top,
    Size size = const Size(400, 800),
    List overrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = routerFor(top: top);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('app: five bottom tabs in the requested order', (tester) async {
    await pumpShell(tester, top: false);
    expect(find.byType(NavigationBar), findsOneWidget);
    final labels = [
      for (final d in tester.widgetList<NavigationDestination>(
        find.byType(NavigationDestination),
      ))
        d.label,
    ];
    expect(labels, ['Home', 'History', 'Log', 'Muscle map', 'Profile']);
    expect(find.text('page /home'), findsOneWidget);
  });

  testWidgets('app: tapping a tab and swiping both navigate', (tester) async {
    final router = await pumpShell(tester, top: false);
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, Routes.logWorkout);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, Routes.muscleMap);

    // The 3D map keeps horizontal drags for rotating the model.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, Routes.muscleMap);
  });

  testWidgets('app: the profile tab has the hamburger menu', (tester) async {
    await pumpShell(tester, top: false);
    expect(find.byTooltip('Profile menu'), findsNothing);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Profile menu'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Change theme'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('web: a top bar, no bottom bar, no swiping', (tester) async {
    final router = await pumpShell(
      tester,
      top: true,
      size: const Size(1280, 800),
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('History'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, Routes.home);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, Routes.history);
    expect(find.text('page /history'), findsOneWidget);
  });

  testWidgets('web: narrow windows drop the labels, not the tabs', (
    tester,
  ) async {
    await pumpShell(tester, top: true, size: const Size(375, 700));
    expect(find.byTooltip('Muscle map'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app: the rest timer opens full screen; ✕ shrinks it to a bar', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 5, 9);
    await pumpShell(
      tester,
      top: false,
      overrides: [
        restClockProvider.overrideWithValue(() => now),
        restVibrateProvider.overrideWithValue((_) async {}),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(restTimerProvider.notifier)
        .start(const Duration(seconds: 90));
    await tester.pump();
    expect(find.byType(RestTimerOverlay), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    expect(find.text('Skip rest'), findsOneWidget);
    expect(find.text('Rest 1:30'), findsNothing);

    await tester.tap(find.byTooltip('Close rest timer'));
    await tester.pump();
    expect(find.text('1:30'), findsNothing);
    expect(find.text('Rest 1:30'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('Rest 1:30'), findsNothing);
  });

  testWidgets('web: the rest timer is a bar, never full screen', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 5, 9);
    await pumpShell(
      tester,
      top: true,
      size: const Size(1280, 800),
      overrides: [
        restClockProvider.overrideWithValue(() => now),
        restVibrateProvider.overrideWithValue((_) async {}),
      ],
    );
    ProviderScope.containerOf(tester.element(find.byType(AppShell)))
        .read(restTimerProvider.notifier)
        .start(const Duration(seconds: 90));
    await tester.pump();
    expect(find.text('Rest 1:30'), findsOneWidget);
    expect(find.byTooltip('Close rest timer'), findsNothing);
  });
}
