import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/router/app_router.dart';
import 'package:lionfit/core/theme/app_theme.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/admin/domain/admin_models.dart';
import 'package:lionfit/features/admin/presentation/admin_screen.dart';
import 'package:lionfit/features/profile/presentation/change_password_sheet.dart';
import 'package:lionfit/features/profile/presentation/plan_settings_sheet.dart';
import 'package:lionfit/features/profile/presentation/profile_edit_sheet.dart';
import 'package:lionfit/features/workout/data/workout_repository.dart';
import 'package:lionfit/features/workout/domain/equipment_item.dart';
import 'package:lionfit/features/workout/domain/training_profile.dart';
import 'package:lionfit/features/workout/domain/workout_models.dart';
import 'package:lionfit/features/workout/presentation/rest_timer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bench = CatalogExercise(
  id: 'bench',
  slug: 'barbell_bench_press',
  name: 'Barbell Bench Press',
  primaryMuscleGroups: [MuscleGroup.chestLower],
  requiredEquipment: ['bench_press'],
  movementPattern: 'horizontal_push',
);
const _treadmill = CatalogExercise(
  id: 'tread',
  slug: 'treadmill_run',
  name: 'Treadmill Run',
  primaryMuscleGroups: [MuscleGroup.quads],
  requiredEquipment: ['treadmill'],
  movementPattern: 'cardio',
);

/// Saves in memory instead of Supabase.
class _MemoryRepository extends WorkoutRepository {
  _MemoryRepository() : super(SupabaseClient('http://localhost', 'test-key'));

  final saved = <NewSet>[];

  @override
  Future<String?> findWorkoutOn(DateTime day) async => null;

  @override
  Future<String> createWorkout(DateTime day) async => 'w1';

  @override
  Future<SetRecord> logSet({
    required String workoutId,
    required int setIndex,
    required NewSet set,
  }) async {
    saved.add(set);
    return SetRecord(
      id: 's${saved.length}',
      workoutId: workoutId,
      exerciseId: set.exerciseId,
      setIndex: setIndex,
      setType: set.setType,
      unit: set.unit,
      weight: set.weight,
      reps: set.reps,
      performedOn: calendarDay(DateTime.now()),
    );
  }
}

void main() {
  group('every logged set starts the rest timer', () {
    late _MemoryRepository repo;
    late ProviderContainer container;
    var now = DateTime(2026, 11, 5, 9);

    setUp(() {
      repo = _MemoryRepository();
      container = ProviderContainer(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(repo),
          exerciseCatalogProvider.overrideWith(
            (_) async => const [_bench, _treadmill],
          ),
          trainingProfileProvider.overrideWith(
            (_) async => const TrainingProfile(restTimerSeconds: 120),
          ),
          trainingHistoryProvider.overrideWith((_) async => const []),
          restClockProvider.overrideWithValue(() => now),
          restVibrateProvider.overrideWithValue((_) async {}),
        ],
      );
      addTearDown(container.dispose);
    });

    NewSet benchSet() => const NewSet(
      exerciseId: 'bench',
      setType: SetType.working,
      unit: WeightUnit.lb,
      weight: 135,
      reps: 10,
    );

    test('one set saved, one 2:00 rest started; again for the next', () async {
      await container.read(exerciseCatalogProvider.future);
      await container.read(trainingProfileProvider.future);
      final session = container.read(todaySessionProvider.notifier);

      await session.logSet(benchSet());
      expect(repo.saved, hasLength(1));
      var rest = container.read(restTimerProvider)!;
      expect(rest.total, const Duration(seconds: 120));

      container.read(restTimerProvider.notifier).dismiss();
      now = now.add(const Duration(minutes: 3));
      await session.logSet(benchSet());
      expect(repo.saved, hasLength(2));
      rest = container.read(restTimerProvider)!;
      expect(rest.remaining(now), const Duration(seconds: 120));
      expect(
        container.read(todaySessionProvider).value!.setsFor('bench'),
        hasLength(2),
      );
    });

    test('cardio does not start a rest', () async {
      await container.read(exerciseCatalogProvider.future);
      await container
          .read(todaySessionProvider.notifier)
          .logSet(
            const NewSet(
              exerciseId: 'tread',
              setType: SetType.working,
              unit: WeightUnit.lb,
              reps: 20,
            ),
          );
      expect(container.read(restTimerProvider), isNull);
    });
  });

  group('admin access', () {
    test('/admin is for admins only, on the same login', () {
      String? go(bool? admin) => redirectFor(
        location: Routes.admin,
        signedIn: true,
        needsOnboarding: false,
        isAdmin: admin,
      );
      expect(go(true), isNull);
      expect(go(false), Routes.home);
      // Profile still loading: wait rather than bounce an admin away.
      expect(go(null), isNull);
      expect(
        redirectFor(
          location: Routes.admin,
          signedIn: false,
          needsOnboarding: false,
          isAdmin: true,
        ),
        Routes.landing,
      );
    });

    test('the role is read, and never written back', () {
      final p = TrainingProfile.fromRow({
        'role': 'admin',
        'goal': 'general_fitness',
        'onboarding_completed_at': '2026-11-01T00:00:00Z',
      });
      expect(p.isAdmin, isTrue);
      expect(p.toRow().keys, isNot(contains('role')));
      expect(TrainingProfile.fromRow({'role': 'member'}).isAdmin, isFalse);
    });
  });

  group('admin models', () {
    test('slugify makes a valid ID', () {
      expect(slugify('Incline DB Press (45°)'), 'incline_db_press_45');
      expect(slugify('  Leg  Press '), 'leg_press');
      expect(slugify('45 Degree Hyper'), 'x_45_degree_hyper');
      expect(kSlugPattern.hasMatch(slugify('Cable Fly - High to Low')), isTrue);
    });

    test('an exercise draft says what is missing, then serialises', () {
      var draft = const ExerciseDraft(
        name: 'Cable Fly',
        slug: 'cable_fly',
        primary: {},
        secondary: {},
        equipment: {'functional_trainer'},
        movementPattern: 'isolation',
      );
      expect(
        draft.problem(knownEquipment: {'functional_trainer'}, isNew: true),
        contains('primary muscle'),
      );
      draft = const ExerciseDraft(
        name: 'Cable Fly',
        slug: 'cable_fly',
        primary: {MuscleGroup.chestUpper},
        secondary: {MuscleGroup.chestUpper, MuscleGroup.deltsFront},
        equipment: {'functional_trainer', 'mystery_rack'},
        movementPattern: 'isolation',
      );
      expect(
        draft.problem(knownEquipment: {'functional_trainer'}),
        contains('mystery_rack'),
      );
      draft = const ExerciseDraft(
        name: ' Cable Fly ',
        slug: 'cable_fly',
        primary: {MuscleGroup.chestUpper},
        secondary: {MuscleGroup.chestUpper, MuscleGroup.deltsFront},
        equipment: {'functional_trainer', 'bodyweight'},
        movementPattern: 'isolation',
      );
      expect(draft.problem(knownEquipment: {'functional_trainer'}), isNull);
      final row = draft.toRow(includeSlug: true);
      expect(row['name'], 'Cable Fly');
      expect(row['slug'], 'cable_fly');
      // A group is never both primary and secondary.
      expect(row['secondary_muscle_groups'], ['delts_front']);
      expect(draft.toRow().containsKey('slug'), isFalse);
    });
  });

  group('screens', () {
    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      List overrides = const [],
    }) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides.cast(),
          child: MaterialApp(theme: AppTheme.dark, home: child),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Edit profile has no password fields', (tester) async {
      await pump(
        tester,
        const Scaffold(
          body: ProfileEditSheet(initial: TrainingProfile(displayName: 'Pao')),
        ),
      );
      expect(find.textContaining('assword'), findsNothing);
    });

    testWidgets('the plan Change sheet is goal and days only', (tester) async {
      await pump(
        tester,
        const Scaffold(body: PlanSettingsSheet(initial: TrainingProfile())),
      );
      expect(find.text('Goal'), findsOneWidget);
      expect(find.text('Days per week'), findsOneWidget);
      expect(find.textContaining('assword'), findsNothing);
    });

    testWidgets('changing the password asks for the current one first', (
      tester,
    ) async {
      await pump(tester, const Scaffold(body: ChangePasswordSheet()));
      expect(find.text('Current password'), findsOneWidget);
      expect(find.text('New password'), findsOneWidget);
      expect(find.text('Confirm new password'), findsOneWidget);
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your current password.'), findsOneWidget);
    });

    final referenceData = [
      exerciseCatalogProvider.overrideWith((_) async => const [_bench]),
      equipmentProvider.overrideWith(
        (_) async => const [
          EquipmentItem(
            slug: 'bench_press',
            label: 'Flat Barbell Bench Press',
            quantity: 2,
          ),
          EquipmentItem(
            slug: 'leg_press',
            label: 'Leg Press',
            quantity: 1,
            status: EquipmentStatus.outOfService,
          ),
        ],
      ),
    ];

    testWidgets('a member sees "Admins only", not the tools', (tester) async {
      await pump(
        tester,
        const AdminScreen(),
        overrides: [
          ...referenceData,
          trainingProfileProvider.overrideWith(
            (_) async => const TrainingProfile(),
          ),
        ],
      );
      expect(find.text('Admins only'), findsOneWidget);
      expect(find.text('Add equipment'), findsNothing);
    });

    testWidgets('an admin gets equipment and exercise tools', (tester) async {
      await pump(
        tester,
        const AdminScreen(),
        overrides: [
          ...referenceData,
          trainingProfileProvider.overrideWith(
            (_) async => const TrainingProfile(isAdmin: true),
          ),
        ],
      );
      expect(find.text('Admin tools'), findsOneWidget);
      expect(find.text('Flat Barbell Bench Press'), findsOneWidget);
      expect(find.text('Out of service'), findsOneWidget);

      await tester.tap(find.text('Leg Press'));
      await tester.pumpAndSettle();
      expect(find.text('Status'), findsOneWidget);
      expect(find.textContaining('used by 0 active'), findsOneWidget);
      Navigator.of(tester.element(find.text('Status'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Exercises'));
      await tester.pumpAndSettle();
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('Add exercise'), findsOneWidget);
    });
  });
}
