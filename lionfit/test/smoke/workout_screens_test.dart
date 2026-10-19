import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/theme/app_theme.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/muscle_map/presentation/muscle_map_screen.dart';
import 'package:lionfit/features/muscle_map/presentation/muscle_model_view.dart';
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
    requiredEquipment: ['calf_raise_machine'],
    notes: 'DEMO: uses placeholder equipment.',
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

  testWidgets('logger lists logged sets and an empty exercise card', (
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
    expect(find.textContaining('135 lb × 10'), findsNWidgets(3));
    expect(find.text('Log set'), findsNWidgets(2));
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
}

class _FakeSession extends TodaySessionController {
  _FakeSession(this._initial);

  final TodaySession _initial;

  @override
  Future<TodaySession> build() async => _initial;
}
