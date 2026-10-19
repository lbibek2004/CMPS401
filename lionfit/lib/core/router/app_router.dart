import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/landing/landing_screen.dart';
import '../../features/muscle_map/presentation/muscle_map_screen.dart';
import '../../features/workout/presentation/log_workout_screen.dart';
import '../auth/auth_controller.dart';
import '../config/env.dart';
import '../widgets/setup_required_screen.dart';

abstract final class Routes {
  static const landing = '/';
  static const login = '/login';
  static const signUp = '/signup';
  static const home = '/home';
  static const logWorkout = '/log';
  static const muscleMap = '/map';

  /// Routes a signed-out visitor may see.
  static const public = {landing, login, signUp};
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Routes.landing,
    debugLogDiagnostics: Env.isDevelopment,
    routes: [
      GoRoute(path: Routes.landing, builder: (_, _) => const LandingScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.signUp, builder: (_, _) => const SignUpScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: Routes.logWorkout,
        builder: (_, _) => const LogWorkoutScreen(),
      ),
      GoRoute(
        path: Routes.muscleMap,
        builder: (_, _) => const MuscleMapScreen(),
      ),
    ],
    redirect: (context, state) {
      // Without a backend there is nothing to protect and nowhere to sign in.
      if (!Env.hasSupabase || Env.configurationProblem != null) return null;

      final signedIn = ref.read(isSignedInProvider);
      final location = state.matchedLocation;

      if (!signedIn && !Routes.public.contains(location)) return Routes.login;
      if (signedIn && (location == Routes.login || location == Routes.signUp)) {
        return Routes.home;
      }
      return null;
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

  // Re-evaluate redirects the moment auth state flips, so signing in or out
  // navigates without the caller having to push a route itself.
  ref.listen<bool>(isSignedInProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

/// Shown instead of the app when configuration is missing.
Widget? configurationGate() {
  final problem = Env.configurationProblem;
  if (problem == null) return null;
  return SetupRequiredScreen(problem: problem);
}
