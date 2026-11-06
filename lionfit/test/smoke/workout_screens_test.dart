import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/theme/app_theme.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/coach/data/coach_providers.dart';
import 'package:lionfit/features/coach/domain/coach_engine.dart';
import 'package:lionfit/features/coach/domain/weekly_plan.dart';
import 'package:lionfit/features/history/presentation/history_screen.dart';
import 'package:lionfit/features/home/home_screen.dart';
import 'package:lionfit/features/muscle_map/presentation/muscle_map_screen.dart';
import 'package:lionfit/features/muscle_map/presentation/muscle_model_view.dart';
import 'package:lionfit/features/onboarding/presentation/onboarding_screen.dart';
import 'package:lionfit/features/profile/presentation/profile_screen.dart';
import 'package:lionfit/features/workout/data/workout_repository.dart';
import 'package:lionfit/features/workout/domain/workout_models.dart';
import 'package:lionfit/features/workout/presentation/log_workout_screen.dart';

/// The logger and the muscle map against canned data, at real viewport sizes
/// in both themes. No Supabase, no WebGL: the 3D view is swapped for its
/// placeholder.
void main() {
  final today = calendarDay(DateTime.now());

  const bench = CatalogExercise(
    id: 'bench',
    slug: 'barbell_bench_press',
    name: 'Barbell Bench Press',
    primaryMuscleGroups: [MuscleGroup.chestLower],
    secondaryMuscleGroups: [MuscleGroup.triceps, MuscleGroup.deltsFront],
    requiredEquipment: ['bench_press'],
  );
  const calf = CatalogExercise(
    id: 'calf',
    slug: 'machine_calf_raise',
    name: 'Machine Calf Raise',
    primaryMuscleGroups: [MuscleGroup.calves],
    requiredEquipment: ['rotary_calf'],
  );

  SetRecord benchSet(int index) => SetRecord(
    id: 's$index',
    workoutId: 'w1',
    exerciseId: 'bench',
    setIndex: index,
    setType: SetType.working,
    unit: WeightUnit.lb,
    weight: 135,
    reps: 10,
    rpe: 8,
    performedOn: today,
  );

  final sets = [benchSet(1), benchSet(2), benchSet(3)];

  final overrides = [
    exerciseCatalogProvider.overrideWith((ref) async => [bench, calf]),
    equipmentLabelsProvider.overrideWith(
      (ref) async => {'bench_press': 'Bench Press Station'},
    ),
    recentSetsProvider.overrideWith((ref) async => sets),
    trainingHistoryProvider.overrideWith((ref) async => sets),
    todaySessionProvider.overrideWith(
      () => _FakeSession(
        TodaySession(
          day: today,
          workoutId: 'w1',
          sets: sets,
          exerciseOrder: const ['bench', 'calf'],
        ),
      ),
    ),
    muscleModelRendererEnabledProvider.overrideWithValue(false),
  ];

  Future<void> render(
    WidgetTester tester,
    Widget screen, {
    required Size size,
    required ThemeData theme,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: screen,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};
  final viewports = {
    'desktop': const Size(1920, 1080),
    'mobile': const Size(375, 812),
  };
  final screens = <String, Widget>{
    'LogWorkoutScreen': const LogWorkoutScreen(),
    'MuscleMapScreen': const MuscleMapScreen(),
    'HomeScreen': const HomeScreen(),
    'HistoryScreen': const HistoryScreen(),
    'ProfileScreen': const ProfileScreen(),
    'OnboardingScreen': const OnboardingScreen(),
  };

  for (final screen in screens.entries) {
    for (final theme in themes.entries) {
      for (final viewport in viewports.entries) {
        testWidgets(
          '${screen.key} renders on ${viewport.key} in ${theme.key}',
          (tester) async {
            await render(
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
    testWidgets('${screen.key} survives 200% text on mobile', (tester) async {
      await render(
        tester,
        screen.value,
        size: const Size(375, 812),
        theme: AppTheme.dark,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a recorded exercise is folded, the empty one is open', (
    tester,
  ) async {
    await render(
      tester,
      const LogWorkoutScreen(),
      size: const Size(1280, 900),
      theme: AppTheme.light,
    );
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('Machine Calf Raise'), findsOneWidget);
    // Bench is folded to one summary line with an Edit button...
    expect(find.text('3 sets · best 135 lb × 10 · RPE 8'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    // ...and only the calf raise shows a set form.
    expect(find.text('Log set 1'), findsOneWidget);
    expect(find.text('Log set 4'), findsNothing);
    expect(find.text('How hard was it?'), findsOneWidget);
  });

  testWidgets('Edit reopens an exercise and folds the other one', (
    tester,
  ) async {
    await render(
      tester,
      const LogWorkoutScreen(),
      size: const Size(1280, 900),
      theme: AppTheme.light,
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('135 lb × 10'), findsNWidgets(3));
    expect(find.text('Log set 4'), findsOneWidget);
    expect(find.text('Log set 1'), findsNothing);
    expect(find.byTooltip('Edit set 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit set 2'));
    await tester.pumpAndSettle();
    expect(find.text('Edit set 2'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('the effort slider replaces the RPE number box', (tester) async {
    await render(
      tester,
      const LogWorkoutScreen(),
      size: const Size(1280, 900),
      theme: AppTheme.dark,
    );
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('RPE 8'), findsOneWidget);
    expect(find.text('Two reps left'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('tapping an untrained muscle offers an exercise to log', (
    tester,
  ) async {
    await render(
      tester,
      const MuscleMapScreen(),
      size: const Size(1280, 900),
      theme: AppTheme.light,
    );
    await tester.ensureVisible(find.text('Calves'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calves'));
    await tester.pumpAndSettle();
    expect(find.text('What trained it'), findsOneWidget);
    expect(find.text('Suggested to catch up'), findsOneWidget);
    expect(find.text('Machine Calf Raise'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Log').first);
    await tester.pumpAndSettle();
    // One set per log, never several at once.
    expect(find.text('Set 1 of 3'), findsOneWidget);
    expect(find.text('Log set 1'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Reps'), '15');
    await tester.ensureVisible(find.text('Log set 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log set 1'));
    await tester.pumpAndSettle();
    expect(_FakeSession.logged, hasLength(1));
    expect(_FakeSession.logged.single.reps, 15);
    expect(_FakeSession.logged.single.exerciseId, 'calf');
    // The effort rating rides along with the set.
    expect(_FakeSession.logged.single.rpe, isNotNull);
  });

  testWidgets('tapping a trained muscle explains direct vs assisted work', (
    tester,
  ) async {
    await render(
      tester,
      const MuscleMapScreen(),
      size: const Size(1280, 900),
      theme: AppTheme.dark,
    );
    await tester.ensureVisible(find.text('Triceps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Triceps'));
    await tester.pumpAndSettle();
    expect(find.text('Assisted'), findsOneWidget);
    expect(find.textContaining('Only indirect work'), findsOneWidget);
  });

  testWidgets('home shows the plan and progress without a tap', (tester) async {
    await render(
      tester,
      const HomeScreen(),
      size: const Size(1280, 900),
      theme: AppTheme.light,
    );
    expect(find.text("This week's plan"), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Next session'), findsOneWidget);
    expect(find.text('Sets this week'), findsOneWidget);
  });

  testWidgets('history opens on the last 7 days with a slider', (tester) async {
    await render(
      tester,
      const HistoryScreen(),
      size: const Size(1280, 900),
      theme: AppTheme.light,
    );
    expect(find.text('Last 7 days'), findsWidgets);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    await tester.ensureVisible(find.text('Calves'));
    await tester.tap(find.text('Calves'));
    await tester.pumpAndSettle();
    expect(find.text('Barbell Bench Press'), findsNothing);
  });

  testWidgets('muscle map classifies 3 bench sets on day one', (tester) async {
    await render(
      tester,
      const MuscleMapScreen(),
      size: const Size(1280, 900),
      theme: AppTheme.dark,
    );
    // First data is today -> 1-day default window, target 3 sets.
    expect(find.text('Last 1 day'), findsOneWidget);
    expect(find.text('Well trained (1)'), findsOneWidget); // lower chest
    expect(
      find.text('Less trained (2)'),
      findsOneWidget,
    ); // triceps, front delts
    expect(find.text('Untrained (13)'), findsOneWidget);
  });

  testWidgets('today: Log and Replace on the open item, Logged on the done', (
    tester,
  ) async {
    // A fixed plan, so the test does not depend on what weekday it runs.
    SuggestedSet suggest(CatalogExercise e) => SuggestedSet(
      exercise: e,
      unit: WeightUnit.lb,
      weight: 50,
      reps: 10,
      sets: 3,
      targetReps: const RepRange(8, 12),
      basis: SuggestionBasis.firstTime,
      reason: 'Test.',
    );
    final monday = mondayOf(today);
    final plan = WeeklyPlan(
      weekStart: monday,
      weekIndex: 0,
      days: [
        for (var i = 0; i < 7; i++)
          DateTime(monday.year, monday.month, monday.day + i) == today
              ? PlanDay(
                  date: today,
                  kind: PlanDayKind.push,
                  exercises: [suggest(bench), suggest(calf)],
                )
              : PlanDay(
                  date: DateTime(monday.year, monday.month, monday.day + i),
                ),
      ],
    );
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          weeklyPlanProvider.overrideWith((_) async => plan),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // Bench was logged today (3 sets in the fake history): marked, no buttons.
    expect(find.textContaining('Logged · 3 sets'), findsOneWidget);
    // Next session: bench is done today, so it shows next time's load and
    // no second Log button.
    expect(find.text('Done today'), findsOneWidget);
    expect(find.textContaining('Next time:'), findsOneWidget);
    expect(find.text('1 of 2 done'), findsOneWidget);
    // Calf raise is still open: Log and Replace.
    expect(find.text('Replace'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is FilledButton),
        matching: find.text('Log'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a half-done exercise counts its sets and offers the next', (
    tester,
  ) async {
    final monday = mondayOf(today);
    final plan = WeeklyPlan(
      weekStart: monday,
      weekIndex: 0,
      days: [
        for (var i = 0; i < 7; i++)
          DateTime(monday.year, monday.month, monday.day + i) == today
              ? PlanDay(
                  date: today,
                  kind: PlanDayKind.push,
                  exercises: [
                    SuggestedSet(
                      exercise: bench,
                      unit: WeightUnit.lb,
                      weight: 135,
                      reps: 10,
                      sets: 4,
                      targetReps: const RepRange(8, 12),
                      basis: SuggestionBasis.progression,
                      reason: 'Test.',
                    ),
                  ],
                )
              : PlanDay(
                  date: DateTime(monday.year, monday.month, monday.day + i),
                ),
      ],
    );
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...overrides,
          weeklyPlanProvider.overrideWith((_) async => plan),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 of 4 sets'), findsOneWidget);
    expect(find.text('Log set 4'), findsOneWidget);
    // Started exercises are not swapped out from under their sets.
    expect(find.text('Replace'), findsNothing);
    expect(find.text('0 of 1 done'), findsOneWidget);

    await tester.tap(find.text('Log set 4'));
    await tester.pumpAndSettle();
    expect(find.text('Set 4 of 4'), findsOneWidget);
  });

  testWidgets('the survey walks five steps and offers Skip at the end', (
    tester,
  ) async {
    await render(
      tester,
      const OnboardingScreen(),
      size: const Size(375, 812),
      theme: AppTheme.dark,
    );
    expect(find.text('Step 1 of 5'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Experience has no default: Next waits for a choice.
    expect(find.text('How long have you been lifting?'), findsOneWidget);
    // The "not saved yet" notice (no migration 0009 in tests) pushes the
    // choices down on a phone.
    expect(find.textContaining('migration 0009'), findsOneWidget);
    await tester.ensureVisible(find.text('Consistent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consistent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('What can you lift right now?'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Build my plan'), findsOneWidget);
  });
}

class _FakeSession extends TodaySessionController {
  _FakeSession(this._initial) {
    logged.clear();
  }

  final TodaySession _initial;
  static final logged = <NewSet>[];

  @override
  Future<TodaySession> build() async => _initial;

  @override
  Future<void> logSet(NewSet set) async => logged.add(set);
}
