import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/core/training/muscle_status.dart';

void main() {
  final catalog = ExerciseCatalog([
    const ExerciseDefinition(
      id: 'bench',
      name: 'Bench Press',
      equipment: EquipmentType.benchPress,
      primaryMuscleGroups: [MuscleGroup.chestLower],
      secondaryMuscleGroups: [MuscleGroup.triceps, MuscleGroup.deltsFront],
    ),
    const ExerciseDefinition(
      id: 'row',
      name: 'Cable Row',
      equipment: EquipmentType.cableRow,
      primaryMuscleGroups: [MuscleGroup.lats],
      unmappedRegions: [UnmappedRegion.rhomboids],
    ),
  ]);

  final today = DateTime(2026, 10, 17);

  LoggedSet set(
    String exercise,
    DateTime day, {
    SetType type = SetType.working,
    int reps = 10,
  }) => LoggedSet(
    exerciseId: exercise,
    setIndex: 0,
    setType: type,
    weight: 135,
    unit: WeightUnit.lb,
    reps: reps,
    performedAt: day,
  );

  group('hardSetTargetFor', () {
    test('is 10 a week, scaled, with a floor of 3', () {
      expect(hardSetTargetFor(1), 3);
      expect(hardSetTargetFor(7), 10);
      expect(hardSetTargetFor(14), 20);
      expect(hardSetTargetFor(30), closeTo(42.857, 0.001));
    });

    test('rejects windows outside 1-30', () {
      expect(() => hardSetTargetFor(0), throwsArgumentError);
      expect(() => hardSetTargetFor(31), throwsArgumentError);
    });
  });

  group('classifyHardSets', () {
    test('zero is untrained, under target is less, at target is well', () {
      expect(classifyHardSets(0, 10), MuscleTrainingStatus.untrained);
      expect(classifyHardSets(0.5, 10), MuscleTrainingStatus.lessTrained);
      expect(classifyHardSets(9.9, 10), MuscleTrainingStatus.lessTrained);
      expect(classifyHardSets(10, 10), MuscleTrainingStatus.wellTrained);
      expect(classifyHardSets(25, 10), MuscleTrainingStatus.wellTrained);
    });
  });

  group('muscleStatusReport', () {
    test('with no sets every group is red', () {
      final report = muscleStatusReport(
        sets: const [],
        catalog: catalog,
        asOf: today,
        windowDays: 7,
      );
      expect(report.byMuscleGroup, hasLength(16));
      expect(report.countWith(MuscleTrainingStatus.untrained), 16);
      expect(report.hasAnyTraining, isFalse);
    });

    test('3 bench sets in a 1-day window: chest green, triceps yellow', () {
      final report = muscleStatusReport(
        sets: [for (var i = 0; i < 3; i++) set('bench', today)],
        catalog: catalog,
        asOf: today,
        windowDays: 1,
      );
      // 3 sets primary vs target 3.
      expect(
        report.statusOf(MuscleGroup.chestLower),
        MuscleTrainingStatus.wellTrained,
      );
      // 1.5 sets secondary.
      expect(report.byMuscleGroup[MuscleGroup.triceps]!.hardSets, 1.5);
      expect(
        report.statusOf(MuscleGroup.triceps),
        MuscleTrainingStatus.lessTrained,
      );
      expect(
        report.statusOf(MuscleGroup.quads),
        MuscleTrainingStatus.untrained,
      );
    });

    test('the same 3 sets over 7 days are only yellow', () {
      final report = muscleStatusReport(
        sets: [for (var i = 0; i < 3; i++) set('bench', today)],
        catalog: catalog,
        asOf: today,
        windowDays: 7,
      );
      expect(
        report.statusOf(MuscleGroup.chestLower),
        MuscleTrainingStatus.lessTrained,
      );
    });

    test('warm-ups and zero-rep sets do not count', () {
      final report = muscleStatusReport(
        sets: [
          set('bench', today, type: SetType.warmUp),
          set('bench', today, reps: 0),
        ],
        catalog: catalog,
        asOf: today,
        windowDays: 1,
      );
      expect(
        report.statusOf(MuscleGroup.chestLower),
        MuscleTrainingStatus.untrained,
      );
    });

    test('sets outside the window are ignored', () {
      final report = muscleStatusReport(
        sets: [set('bench', today.subtract(const Duration(days: 3)))],
        catalog: catalog,
        asOf: today,
        windowDays: 2,
      );
      expect(
        report.statusOf(MuscleGroup.chestLower),
        MuscleTrainingStatus.untrained,
      );
    });

    test('rows light up lats, including the rhomboid fallback share', () {
      final report = muscleStatusReport(
        sets: [set('row', today), set('row', today)],
        catalog: catalog,
        asOf: today,
        windowDays: 1,
      );
      // 2 primary + 2 x 0.5 rhomboid fallback = 3 -> green on a 1-day window.
      expect(report.byMuscleGroup[MuscleGroup.lats]!.hardSets, 3);
      expect(
        report.statusOf(MuscleGroup.lats),
        MuscleTrainingStatus.wellTrained,
      );
    });

    test('unknown exercises are reported, not silently dropped', () {
      final report = muscleStatusReport(
        sets: [set('ghost', today)],
        catalog: catalog,
        asOf: today,
        windowDays: 1,
      );
      expect(report.unknownExerciseIds, {'ghost'});
    });
  });

  group('defaultMapWindowDays', () {
    test('is 7 with no data', () {
      expect(defaultMapWindowDays(const [], asOf: today), 7);
    });

    test('is 1 when the only data is today', () {
      expect(defaultMapWindowDays([set('bench', today)], asOf: today), 1);
    });

    test('spans back to the first logged set, inclusive', () {
      final sets = [
        set('bench', today.subtract(const Duration(days: 4))),
        set('bench', today),
      ];
      expect(defaultMapWindowDays(sets, asOf: today), 5);
    });

    test('caps at 30 and ignores warm-ups', () {
      final sets = [
        set('bench', today.subtract(const Duration(days: 90))),
        set(
          'bench',
          today.subtract(const Duration(days: 200)),
          type: SetType.warmUp,
        ),
      ];
      expect(defaultMapWindowDays(sets, asOf: today), 30);
    });
  });
}
