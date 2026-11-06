import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/health/presentation/health_privacy_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/landing/landing_screen.dart';
import '../../features/muscle_map/presentation/muscle_map_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/workout/data/workout_repository.dart';
import '../../features/workout/presentation/log_workout_screen.dart';
import '../auth/auth_controller.dart';
import '../config/env.dart';
import '../widgets/setup_required_screen.dart';
import 'app_shell.dart';
import 'routes.dart';

export 'routes.dart';

/// True once the profile has loaded and says the survey is still owed.
/// False while it loads, so a slow request never traps anyone on /welcome.
final onboardingRequiredProvider = Provider<bool>(
  (ref) => ref.watch(trainingProfileProvider).value?.needsOnboarding ?? false,
);

/// True / false once the profile has loaded; null while it loads, so a
/// refresh on /admin waits for the role instead of bouncing an admin away.
final adminStatusProvider = Provider<bool?>((ref) {
  final profile = ref.watch(trainingProfileProvider);
  return profile.hasValue ? profile.value!.isAdmin : null;
});

/// Where a navigation to [location] should go instead, or null to allow it.
///
/// Pure so the rules can be tested without a router:
/// * signed out: only the public pages; anything else goes to the landing
///   page;
/// * signed in: the public pages (landing included) go straight to home -
///   the landing page is only for signed-out visitors;
/// * signed in with the survey owed: everything goes to /welcome;
/// * /admin only for admins - anyone known not to be one goes home. Being an
///   admin is a property of the same login, not a separate sign-in;
/// * the open pages (the health privacy policy) for everyone, always.
String? redirectFor({
  required String location,
  required bool signedIn,
  required bool needsOnboarding,
  bool? isAdmin,
}) {
  if (Routes.open.contains(location)) return null;
  if (!signedIn) {
    return Routes.public.contains(location) ? null : Routes.landing;
  }
  if (needsOnboarding && location != Routes.welcome) return Routes.welcome;
  if (Routes.public.contains(location)) return Routes.home;
  if (location.startsWith(Routes.admin) && isAdmin == false) {
    return Routes.home;
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Routes.landing,
    debugLogDiagnostics: Env.isDevelopment,
    routes: [
      GoRoute(path: Routes.landing, builder: (_, _) => const LandingScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.signUp, builder: (_, _) => const SignUpScreen()),
      GoRoute(
        path: Routes.welcome,
        builder: (_, _) => const OnboardingScreen(),
      ),
      GoRoute(path: Routes.admin, builder: (_, _) => const AdminScreen()),
      GoRoute(
        path: Routes.healthPrivacy,
        builder: (_, _) => const HealthPrivacyScreen(),
      ),
      StatefulShellRoute(
        builder: (_, _, navigationShell) => navigationShell,
        navigatorContainerBuilder: (context, navigationShell, children) =>
            AppShell(navigationShell: navigationShell, children: children),
        branches: [
          for (final (path, screen) in const [
            (Routes.home, HomeScreen()),
            (Routes.history, HistoryScreen()),
            (Routes.logWorkout, LogWorkoutScreen()),
            (Routes.muscleMap, MuscleMapScreen()),
            (Routes.profile, ProfileScreen()),
          ])
            StatefulShellBranch(
              // Built up front so a swipe never lands on an empty page.
              preload: true,
              routes: [
                GoRoute(
                  path: path,
                  pageBuilder: (_, _) => NoTransitionPage(child: screen),
                ),
              ],
            ),
        ],
      ),
    ],
    redirect: (context, state) {
      // Without a backend there is nothing to protect and nowhere to sign in.
      if (!Env.hasSupabase || Env.configurationProblem != null) return null;
      return redirectFor(
        location: state.matchedLocation,
        signedIn: ref.read(isSignedInProvider),
        needsOnboarding: ref.read(onboardingRequiredProvider),
        isAdmin: ref.read(adminStatusProvider),
      );
    },
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(state.uri.toString()),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(Routes.landing),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    ),
  );

  // Re-evaluate redirects the moment auth state flips or the profile says
  // the survey is owed, so callers never have to push a route themselves.
  ref.listen<bool>(isSignedInProvider, (_, _) => router.refresh());
  ref.listen<bool>(onboardingRequiredProvider, (_, _) => router.refresh());
  ref.listen<bool?>(adminStatusProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

/// Shown instead of the app when configuration is missing.
Widget? configurationGate() {
  final problem = Env.configurationProblem;
  if (problem == null) return null;
  return SetupRequiredScreen(problem: problem);
}
