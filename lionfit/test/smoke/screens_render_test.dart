import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/theme/app_theme.dart';
import 'package:lionfit/features/auth/login_screen.dart';
import 'package:lionfit/features/auth/signup_screen.dart';
import 'package:lionfit/features/home/home_screen.dart';
import 'package:lionfit/features/landing/landing_screen.dart';

/// Renders every screen against the real theme at real viewport sizes.
///
/// A RenderFlex overflow throws during pump, so these fail loudly on a
/// responsive regression rather than quietly painting a yellow-and-black bar.
void main() {
  Future<void> renderAt(
    WidgetTester tester,
    Widget screen, {
    required Size size,
    required ThemeData theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: theme, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  const desktop = Size(1920, 1080);
  const laptop = Size(1280, 800);
  const mobile = Size(375, 812);

  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};
  final viewports = {'desktop': desktop, 'laptop': laptop, 'mobile': mobile};
  final screens = <String, Widget>{
    'LandingScreen': const LandingScreen(),
    'LoginScreen': const LoginScreen(),
    'SignUpScreen': const SignUpScreen(),
    'HomeScreen': const HomeScreen(),
  };

  for (final screen in screens.entries) {
    for (final theme in themes.entries) {
      for (final viewport in viewports.entries) {
        testWidgets(
          '${screen.key} renders on ${viewport.key} in ${theme.key}',
          (tester) async {
            await renderAt(
              tester,
              screen.value,
              size: viewport.value,
              theme: theme.value,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('landing page shows both calls to action', (tester) async {
    await renderAt(
      tester,
      const LandingScreen(),
      size: desktop,
      theme: AppTheme.light,
    );
    expect(find.textContaining('LionFit'), findsWidgets);
    expect(
      find.textContaining(RegExp('sign in', caseSensitive: false)),
      findsWidgets,
    );
  });

  testWidgets('login form exposes email and password fields', (tester) async {
    await renderAt(
      tester,
      const LoginScreen(),
      size: laptop,
      theme: AppTheme.dark,
    );
    expect(find.byType(TextFormField), findsAtLeast(2));
  });

  testWidgets('sign-up form exposes name, email and both password fields', (
    tester,
  ) async {
    await renderAt(
      tester,
      const SignUpScreen(),
      size: laptop,
      theme: AppTheme.dark,
    );
    expect(find.byType(TextFormField), findsAtLeast(4));
  });

  testWidgets('screens survive 200% text scaling without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = mobile;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final screen in screens.entries) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: screen.value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '${screen.key} at 200% text',
      );
    }
  });
}
