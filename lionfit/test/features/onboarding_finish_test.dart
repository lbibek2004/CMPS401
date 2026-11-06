import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lionfit/core/router/app_router.dart';
import 'package:lionfit/core/theme/app_theme.dart';
import 'package:lionfit/features/onboarding/presentation/onboarding_screen.dart';
import 'package:lionfit/features/workout/data/workout_repository.dart';
import 'package:lionfit/features/workout/domain/training_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A profiles row behind a slow network: every call takes a moment, like the
/// real thing, so a reload is still in flight when the next line runs.
class _SlowProfileRepository extends WorkoutRepository {
  _SlowProfileRepository({this.saveSticks = true})
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          // No token-refresh timer left running inside the widget test.
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  /// False = the server accepts the update but nothing changes (what RLS
  /// does to an UPDATE it refuses: zero rows, no error).
  final bool saveSticks;

  Map<String, dynamic> row = {
    'role': 'member',
    'goal': 'general_fitness',
    'days_per_week': 3,
    'unit_preference': 'lb',
    'effort_preference': 'rpe',
    'target_rpe': 8,
    'rest_timer_seconds': 90,
    'theme_preference': 'system',
    'onboarding_completed_at': null,
  };

  static const _latency = Duration(milliseconds: 300);

  @override
  Future<TrainingProfile> fetchProfile() async {
    await Future<void>.delayed(_latency);
    return TrainingProfile.fromRow(Map.of(row));
  }

  @override
  Future<void> updateProfile(TrainingProfile profile) async {
    await Future<void>.delayed(_latency);
    if (saveSticks) row = {...row, ...profile.toRow()};
  }

  @override
  Future<List<StrengthBaseline>> fetchBaselines() async => const [];

  @override
  Future<void> replaceBaselines(List<StrengthBaseline> baselines) async {
    await Future<void>.delayed(_latency);
  }
}

void main() {
  /// The app's redirect rules, wired to the providers the same way
  /// `routerProvider` wires them, around the real survey screen.
  Future<GoRouter> pumpSurvey(
    WidgetTester tester,
    _SlowProfileRepository repo,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(repo),
        exerciseCatalogProvider.overrideWith((_) async => const []),
        equipmentProvider.overrideWith((_) async => const []),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: Routes.home,
      routes: [
        GoRoute(
          path: Routes.welcome,
          builder: (_, _) => const OnboardingScreen(),
        ),
        GoRoute(
          path: Routes.home,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
      ],
      redirect: (_, state) => redirectFor(
        location: state.matchedLocation,
        signedIn: true,
        needsOnboarding: container.read(onboardingRequiredProvider),
        isAdmin: container.read(adminStatusProvider),
      ),
    );
    container.listen<bool>(
      onboardingRequiredProvider,
      (_, _) => router.refresh(),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    // Profile loads, says the survey is owed, router sends us to /welcome.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return router;
  }

  /// Answers the five steps and taps "Build my plan".
  Future<void> answerAndFinish(WidgetTester tester) async {
    expect(find.text('Step 1 of 5'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.ensureVisible(find.text('Consistent'));
    await tester.tap(find.text('Consistent'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Build my plan'));
  }

  /// No pumpAndSettle: a stuck spinner never settles, and that is the bug.
  Future<void> wait(WidgetTester tester, Duration total) async {
    for (
      var t = Duration.zero;
      t < total;
      t += const Duration(milliseconds: 100)
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('finishing the survey lands on home, not a spinner', (
    tester,
  ) async {
    final repo = _SlowProfileRepository();
    final router = await pumpSurvey(tester, repo);
    expect(router.state.matchedLocation, Routes.welcome);

    await answerAndFinish(tester);
    await wait(tester, const Duration(seconds: 5));

    expect(repo.row['onboarding_completed_at'], isNotNull);
    expect(router.state.matchedLocation, Routes.home);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a save the server ignores says so instead of spinning', (
    tester,
  ) async {
    final repo = _SlowProfileRepository(saveSticks: false);
    final router = await pumpSurvey(tester, repo);

    await answerAndFinish(tester);
    await wait(tester, const Duration(seconds: 5));

    expect(router.state.matchedLocation, Routes.welcome);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('not saved'), findsOneWidget);
  });
}
