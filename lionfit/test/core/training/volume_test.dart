// Weekly volume and the 0-1 muscle intensity that drives the 3D map: what
// counts, what gets attributed where, and how a window behaves at the edges.
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/core/training/volume.dart';

void main() {
  final catalog = ExerciseCatalog([
    const ExerciseDefinition(
      id: 'bench_press',
      name: 'Barbell bench press',
      equipment: EquipmentType.benchPress,
      primaryMuscleGroups: [MuscleGroup.chestLower],
      secondaryMuscleGroups: [MuscleGroup.triceps, MuscleGroup.deltsFront],
    ),
    const ExerciseDefinition(
      id: 'deadlift',
      name: 'Deadlift',
      equipment: EquipmentType.barbell,
      primaryMuscleGroups: [MuscleGroup.glutes, MuscleGroup.hamstrings],
      secondaryMuscleGroups: [MuscleGroup.trapsUpper, MuscleGroup.forearms],
      // No geometry exists for the erector spinae; its volume is attributed.
      unmappedRegions: [UnmappedRegion.erectorSpinae],
    ),
    const ExerciseDefinition(
      id: 'pull_up',
      name: 'Pull-up',
      equipment: EquipmentType.bodyweight,
      primaryMuscleGroups: [MuscleGroup.lats],
      secondaryMuscleGroups: [MuscleGroup.biceps],
      unmappedRegions: [UnmappedRegion.rhomboids],
    ),
  ]);

  final engine = VolumeEngine(catalog: catalog);

  LoggedSet log({
    required String exerciseId,
    required DateTime on,
    required double lb,
    required int reps,
    int index = 0,
    SetType type = SetType.working,
  }) => LoggedSet(
    exerciseId: exerciseId,
    setIndex: index,
    setType: type,
    weight: lb,
    unit: WeightUnit.lb,
    reps: reps,
    performedAt: on,
  );

  List<LoggedSet> benchSets(DateTime on, {int count = 3, double lb = 135}) => [
    for (var i = 0; i < count; i++)
      log(exerciseId: 'bench_press', on: on, lb: lb, reps: 10, index: i),
  ];

  group('a week of volume', () {
    test('runs Monday to Sunday around the day asked about', () {
      final report = engine.weeklyVolume(
        benchSets(DateTime(2026, 10, 7)),
        weekOf: DateTime(2026, 10, 7, 18, 30),
      );

      expect(report.weekStart, DateTime(2026, 10, 5));
      expect(report.weekEnd, DateTime(2026, 10, 11));
      expect(report.weekStart.weekday, DateTime.monday);
    });

    test('adds up sets, reps and tonnage for the muscle doing the work', () {
      final report = engine.weeklyVolume(
        benchSets(DateTime(2026, 10, 7)),
        weekOf: DateTime(2026, 10, 7),
      );

      final chest = report.forGroup(MuscleGroup.chestLower);
      expect(chest.setCount, 3);
      expect(chest.reps, 30);
      expect(chest.tonnageLb, 3 * 10 * 135);
    });

    test('gives assisting muscles a half share of the same set', () {
      final report = engine.weeklyVolume(
        benchSets(DateTime(2026, 10, 7)),
        weekOf: DateTime(2026, 10, 7),
      );

      expect(report.forGroup(MuscleGroup.triceps).setCount, 1.5);
      expect(report.forGroup(MuscleGroup.deltsFront).setCount, 1.5);
      expect(report.forGroup(MuscleGroup.triceps).tonnageLb, 3 * 10 * 135 / 2);
    });

    test('leaves warm-ups out: they are not stimulus', () {
      final report = engine.weeklyVolume([
        log(
          exerciseId: 'bench_press',
          on: DateTime(2026, 10, 7),
          lb: 45,
          reps: 10,
          type: SetType.warmUp,
        ),
        ...benchSets(DateTime(2026, 10, 7)),
      ], weekOf: DateTime(2026, 10, 7));

      expect(report.forGroup(MuscleGroup.chestLower).setCount, 3);
    });

    test('counts a drop set, which is real work even if it is lighter', () {
      final report = engine.weeklyVolume([
        ...benchSets(DateTime(2026, 10, 7)),
        log(
          exerciseId: 'bench_press',
          on: DateTime(2026, 10, 7),
          lb: 95,
          reps: 12,
          index: 3,
          type: SetType.dropSet,
        ),
      ], weekOf: DateTime(2026, 10, 7));

      expect(report.forGroup(MuscleGroup.chestLower).setCount, 4);
    });

    test('ignores work logged in a neighbouring week', () {
      final report = engine.weeklyVolume([
        ...benchSets(DateTime(2026, 10, 4)), // the Sunday before
        ...benchSets(DateTime(2026, 10, 12)), // the Monday after
        ...benchSets(DateTime(2026, 10, 5)), // the Monday itself
      ], weekOf: DateTime(2026, 10, 7));

      expect(report.forGroup(MuscleGroup.chestLower).setCount, 3);
    });

    test('offers all 16 groups so the model can be repainted in one pass', () {
      final report = engine.weeklyVolume(
        benchSets(DateTime(2026, 10, 7)),
        weekOf: DateTime(2026, 10, 7),
      );

      expect(report.byMuscleGroup, hasLength(16));
      expect(report.forGroup(MuscleGroup.calves), MuscleVolume.zero);
      expect(report.trainedGroups.first, MuscleGroup.chestLower);
    });

    test(
      'reports an exercise missing from the catalog instead of losing it',
      () {
        final report = engine.weeklyVolume([
          log(
            exerciseId: 'leg_press',
            on: DateTime(2026, 10, 7),
            lb: 300,
            reps: 10,
          ),
        ], weekOf: DateTime(2026, 10, 7));

        expect(report.unknownExerciseIds, {'leg_press'});
        expect(report.totalHardSets, 0);
      },
    );
  });

  group('muscles the 3D model cannot draw', () {
    final deadlifts = [
      log(exerciseId: 'deadlift', on: DateTime(2026, 10, 7), lb: 225, reps: 5),
      log(
        exerciseId: 'deadlift',
        on: DateTime(2026, 10, 7),
        lb: 225,
        reps: 5,
        index: 1,
      ),
    ];

    test('still light something up rather than nothing at all', () {
      final report = engine.weeklyVolume(
        deadlifts,
        weekOf: DateTime(2026, 10, 7),
      );

      // 2 primary sets for the glutes, plus a half share of the lower-back
      // work that has nowhere else to go.
      expect(report.forGroup(MuscleGroup.glutes).setCount, 3);
      expect(report.forGroup(MuscleGroup.hamstrings).setCount, 2);
    });

    test('keep their own volume visible so nothing is silently dropped', () {
      final report = engine.weeklyVolume(
        deadlifts,
        weekOf: DateTime(2026, 10, 7),
      );

      expect(
        report.byUnmappedRegion[UnmappedRegion.erectorSpinae]?.setCount,
        2,
      );
      expect(UnmappedRegion.erectorSpinae.mapsTo, MuscleGroup.glutes);
    });

    test('can be kept off the map entirely when a caller prefers that', () {
      final strict = VolumeEngine(
        catalog: catalog,
        unmappedPolicy: UnmappedVolumePolicy.reportOnly,
      );
      final report = strict.weeklyVolume(
        deadlifts,
        weekOf: DateTime(2026, 10, 7),
      );

      expect(report.forGroup(MuscleGroup.glutes).setCount, 2);
      expect(
        report.byUnmappedRegion[UnmappedRegion.erectorSpinae]?.setCount,
        2,
      );
    });
  });

  group('the rolling intensity window', () {
    test('reaches back into the previous month without losing a day', () {
      // 30 days ending 2 March 2026 starts on 1 February - the kind of
      // arithmetic that breaks when you subtract Duration(days: 30).
      final report = engine.muscleIntensity(
        sets: [
          ...benchSets(DateTime(2026, 2, 1)), // first day in the window
          ...benchSets(DateTime(2026, 1, 31)), // one day too early
        ],
        asOf: DateTime(2026, 3, 2, 21),
        windowDays: 30,
      );

      expect(report.windowStart, DateTime(2026, 2, 1));
      expect(report.windowEnd, DateTime(2026, 3, 2));
      expect(
        report.rawByMuscleGroup[MuscleGroup.chestLower],
        3,
        reason: 'only the February sets are inside the window',
      );
    });

    test('handles a single-day window', () {
      final report = engine.muscleIntensity(
        sets: benchSets(DateTime(2026, 10, 11)),
        asOf: DateTime(2026, 10, 11, 23),
        windowDays: 1,
      );

      expect(report.windowStart, report.windowEnd);
      expect(report.forGroup(MuscleGroup.chestLower), 1.0);
    });

    test('refuses a window outside the 1-30 days the UI offers', () {
      expect(
        () => engine.muscleIntensity(
          sets: const [],
          asOf: DateTime(2026, 10, 11),
          windowDays: 31,
        ),
        throwsArgumentError,
      );
      expect(
        () => engine.muscleIntensity(
          sets: const [],
          asOf: DateTime(2026, 10, 11),
          windowDays: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('intensity normalization', () {
    test(
      'measures a lifter against their own best window, not an absolute',
      () {
        final report = engine.muscleIntensity(
          sets: [
            // A heavy chest week earlier in the month...
            ...benchSets(DateTime(2026, 10, 5), count: 10),
            // ...and half as much inside the current window.
            ...benchSets(DateTime(2026, 10, 28), count: 5),
          ],
          asOf: DateTime(2026, 10, 31),
          windowDays: 7,
        );

        expect(report.baseline, IntensityBaseline.ownHistory);
        expect(report.forGroup(MuscleGroup.chestLower), closeTo(0.5, 1e-9));
      },
    );

    test('reads 1.0 when the lifter is at their own ceiling', () {
      final report = engine.muscleIntensity(
        sets: [
          ...benchSets(DateTime(2026, 10, 5), count: 5),
          ...benchSets(DateTime(2026, 10, 28), count: 10),
        ],
        asOf: DateTime(2026, 10, 31),
        windowDays: 7,
      );

      expect(report.forGroup(MuscleGroup.chestLower), 1.0);
    });

    test('still gives a brand-new lifter a readable map', () {
      // Nothing logged before this window, so there is no personal history to
      // normalize against: the hardest-trained group becomes the reference and
      // the report says so.
      final report = engine.muscleIntensity(
        sets: [
          ...benchSets(DateTime(2026, 10, 7), count: 4),
          log(exerciseId: 'pull_up', on: DateTime(2026, 10, 8), lb: 0, reps: 8),
          log(
            exerciseId: 'pull_up',
            on: DateTime(2026, 10, 8),
            lb: 0,
            reps: 8,
            index: 1,
          ),
        ],
        asOf: DateTime(2026, 10, 11),
        windowDays: 7,
      );

      expect(report.baseline, IntensityBaseline.currentWindow);
      expect(report.forGroup(MuscleGroup.chestLower), 1.0);
      expect(report.forGroup(MuscleGroup.lats), closeTo(0.75, 1e-9));
      expect(report.forGroup(MuscleGroup.triceps), closeTo(0.5, 1e-9));
    });

    test('says plainly when there is nothing to show', () {
      final report = engine.muscleIntensity(
        sets: const [],
        asOf: DateTime(2026, 10, 11),
        windowDays: 30,
      );

      expect(report.baseline, IntensityBaseline.noData);
      expect(report.byMuscleGroup, hasLength(16));
      expect(report.byMuscleGroup.values.every((value) => value == 0), isTrue);
      expect(report.trainedGroups, isEmpty);
    });

    test('keeps every value paintable: 16 keys, all between 0 and 1', () {
      final report = engine.muscleIntensity(
        sets: [
          ...benchSets(DateTime(2026, 10, 5), count: 8),
          ...benchSets(DateTime(2026, 10, 28), count: 3),
          log(
            exerciseId: 'deadlift',
            on: DateTime(2026, 10, 29),
            lb: 315,
            reps: 3,
          ),
        ],
        asOf: DateTime(2026, 10, 31),
        windowDays: 7,
      );

      expect(report.byMuscleGroup, hasLength(16));
      for (final value in report.byMuscleGroup.values) {
        expect(value, inInclusiveRange(0, 1));
      }
    });

    test('lights up the lats for pull-ups, which carry no tonnage at all', () {
      final sets = [
        log(exerciseId: 'pull_up', on: DateTime(2026, 10, 10), lb: 0, reps: 10),
        log(
          exerciseId: 'pull_up',
          on: DateTime(2026, 10, 10),
          lb: 0,
          reps: 10,
          index: 1,
        ),
      ];

      final bySets = engine.muscleIntensity(
        sets: sets,
        asOf: DateTime(2026, 10, 11),
        windowDays: 7,
      );
      final byTonnage = engine.muscleIntensity(
        sets: sets,
        asOf: DateTime(2026, 10, 11),
        windowDays: 7,
        metric: IntensityMetric.tonnage,
      );

      expect(bySets.forGroup(MuscleGroup.lats), 1.0);
      // The exact reason hard sets are the default metric: by tonnage this
      // lifter's back day never happened.
      expect(byTonnage.forGroup(MuscleGroup.lats), 0);
    });

    test('blends the two metrics when a caller asks for both', () {
      final report = engine.muscleIntensity(
        sets: [
          ...benchSets(DateTime(2026, 10, 10), count: 4),
          log(
            exerciseId: 'pull_up',
            on: DateTime(2026, 10, 10),
            lb: 0,
            reps: 10,
          ),
        ],
        asOf: DateTime(2026, 10, 11),
        windowDays: 7,
        metric: IntensityMetric.blended,
      );

      expect(report.metric, IntensityMetric.blended);
      expect(report.forGroup(MuscleGroup.chestLower), 1.0);
      expect(report.forGroup(MuscleGroup.lats), greaterThan(0));
      expect(report.forGroup(MuscleGroup.lats), lessThan(1));
    });
  });
}
