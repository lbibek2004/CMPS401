// Behaviour of the training domain model: the muscle-group contract with the
// 3D asset and the database, unit conversion, effort ratings, and how raw logged
// sets become sessions.
//
// `flutter_test` is only the runner here - the code under test imports nothing
// from Flutter.
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';

void main() {
  group('the muscle group vocabulary', () {
    test('is exactly the 16 keys the GLB materials and the database use', () {
      // Verbatim from CLAUDE.md -> Assets, which is verbatim from
      // `node tool/inspect_glb.js assets/muscleAnatomy.glb`. If this list and
      // the enum ever disagree, the 3D map silently paints nothing.
      const materialNames = <String>[
        'abs',
        'adductors',
        'biceps',
        'calves',
        'chest_lower',
        'chest_upper',
        'delts_front',
        'delts_rear',
        'delts_side',
        'forearms',
        'glutes',
        'hamstrings',
        'lats',
        'quads',
        'traps_upper',
        'triceps',
      ];

      expect(MuscleGroup.values, hasLength(16));
      expect(
        MuscleGroup.values.map((group) => group.wireName).toList(),
        materialNames,
      );
    });

    test('round-trips a wire name back to its enum value', () {
      expect(MuscleGroup.fromWireName('chest_upper'), MuscleGroup.chestUpper);
      expect(
        MuscleGroup.tryFromWireName('traps_upper'),
        MuscleGroup.trapsUpper,
      );
    });

    test('refuses a key that is not one of the 16', () {
      // "chestUpper" is the Dart identifier, not the wire name - the kind of
      // mistake that would otherwise reach the GLB as a missing material.
      expect(() => MuscleGroup.fromWireName('chestUpper'), throwsArgumentError);
      expect(MuscleGroup.tryFromWireName('rhomboids'), isNull);
    });

    test('keeps the four muscles with no 3D geometry out of the enum', () {
      final wireNames = MuscleGroup.values.map((group) => group.wireName);
      for (final region in UnmappedRegion.values) {
        expect(wireNames, isNot(contains(region.wireName)));
      }
      // ...but every one of them has a documented place to show up.
      expect(UnmappedRegion.erectorSpinae.mapsTo, MuscleGroup.glutes);
      expect(UnmappedRegion.obliques.mapsTo, MuscleGroup.abs);
      expect(UnmappedRegion.rhomboids.mapsTo, MuscleGroup.lats);
      expect(UnmappedRegion.tibialisAnterior.mapsTo, MuscleGroup.calves);
    });
  });

  group('effort ratings', () {
    test('are either RPE or reps in reserve, never both at once', () {
      final rated = Effort.rpe(8);
      expect(rated, isA<RpeEffort>());
      expect(rated, isNot(isA<RirEffort>()));

      final counted = Effort.rir(2);
      expect(counted, isA<RirEffort>());
      expect(counted, isNot(isA<RpeEffort>()));
    });

    test('describe the same set on either scale', () {
      // RPE = 10 - RIR.
      expect(Effort.rpe(8).repsInReserve, 2);
      expect(Effort.rir(2).rpe, 8);
      expect(Effort.rpe(10).repsInReserve, 0);
      expect(Effort.rir(0).rpe, 10);
    });

    test('refuse an RPE outside the 0-10 scale', () {
      expect(() => Effort.rpe(11), throwsArgumentError);
      expect(() => Effort.rpe(-1), throwsArgumentError);
      expect(() => Effort.rpe(double.nan), throwsArgumentError);
    });

    test('refuse a negative number of reps in reserve', () {
      expect(() => Effort.rir(-1), throwsArgumentError);
    });

    test('read out loud the way a lifter would say them', () {
      expect(Effort.rpe(7.5).label, 'RPE 7.5');
      expect(Effort.rpe(7).label, 'RPE 7');
      expect(Effort.rir(1).label, '1 rep in reserve');
      expect(Effort.rir(3).label, '3 reps in reserve');
    });

    test('are optional - a set logged with neither is still a valid set', () {
      final unrated = LoggedSet(
        exerciseId: 'bench_press',
        setIndex: 0,
        setType: SetType.working,
        weight: 135,
        unit: WeightUnit.lb,
        reps: 8,
        performedAt: DateTime(2026, 10, 5),
      );
      expect(unrated.effort, isNull);
    });
  });

  group('weight units', () {
    test('convert pounds to kilograms and back without drift', () {
      const benchPress = Weight.lb(135);
      expect(benchPress.inKg, closeTo(61.235, 0.001));
      expect(
        benchPress.to(WeightUnit.kg).to(WeightUnit.lb).value,
        closeTo(135, 1e-9),
      );
    });

    test('convert kilograms to pounds and back without drift', () {
      const plates = Weight.kg(60);
      expect(plates.inLb, closeTo(132.277, 0.001));
      expect(
        plates.to(WeightUnit.lb).to(WeightUnit.kg).value,
        closeTo(60, 1e-9),
      );
    });

    test('round for display to a half pound or a tenth of a kilogram', () {
      expect(const Weight.lb(132.277).rounded().value, 132.5);
      expect(
        const Weight.lb(135).to(WeightUnit.kg).rounded().value,
        closeTo(61.2, 1e-9),
      );
      // ...and the label reads like a coach wrote it, not a float.
      expect(
        formatTrimmed(const Weight.lb(135).to(WeightUnit.kg).rounded().value),
        '61.2',
      );
      expect(formatTrimmed(145), '145');
      expect(formatTrimmed(2.5), '2.5');
    });

    test('store a kilogram entry readable in the canonical pound unit', () {
      final metricLog = LoggedSet(
        exerciseId: 'squat',
        setIndex: 0,
        setType: SetType.working,
        weight: 100,
        unit: WeightUnit.kg,
        reps: 5,
        performedAt: DateTime(2026, 10, 5),
      );
      expect(canonicalWeightUnit, WeightUnit.lb);
      expect(metricLog.weight, 100, reason: 'kept as the user typed it');
      expect(metricLog.weightLb, closeTo(220.462, 0.001));
      expect(metricLog.tonnageLb, closeTo(1102.31, 0.01));
    });
  });

  group('a logged set', () {
    test('refuses impossible values', () {
      LoggedSet build({double weight = 100, int reps = 5, int setIndex = 0}) =>
          LoggedSet(
            exerciseId: 'row',
            setIndex: setIndex,
            setType: SetType.working,
            weight: weight,
            unit: WeightUnit.lb,
            reps: reps,
            performedAt: DateTime(2026, 10, 5),
          );

      expect(() => build(weight: -5), throwsArgumentError);
      expect(() => build(reps: -1), throwsArgumentError);
      expect(() => build(setIndex: -1), throwsArgumentError);
      expect(() => build(weight: double.nan), throwsArgumentError);
    });

    test('accepts a failed set: zero reps at a real weight', () {
      final failed = LoggedSet(
        exerciseId: 'bench_press',
        setIndex: 2,
        setType: SetType.working,
        weight: 185,
        unit: WeightUnit.lb,
        reps: 0,
        effort: Effort.rpe(10),
        performedAt: DateTime(2026, 10, 5),
      );
      expect(failed.reps, 0);
      expect(failed.tonnageLb, 0);
    });

    test('accepts bodyweight work at zero load', () {
      final pullUp = LoggedSet(
        exerciseId: 'pull_up',
        setIndex: 0,
        setType: SetType.working,
        weight: 0,
        unit: WeightUnit.lb,
        reps: 10,
        performedAt: DateTime(2026, 10, 5),
      );
      expect(pullUp.tonnageLb, 0);
      expect(pullUp.countsAsVolume, isTrue);
    });
  });

  group('set types', () {
    test('keep warm-ups out of volume and out of load progression', () {
      expect(SetType.warmUp.countsAsVolume, isFalse);
      expect(SetType.warmUp.drivesLoadProgression, isFalse);
    });

    test('count a drop set as volume but never as the load you handled', () {
      // A drop set's weight is deliberately reduced; reading it as capability
      // would ratchet every recommendation downward.
      expect(SetType.dropSet.countsAsVolume, isTrue);
      expect(SetType.dropSet.drivesLoadProgression, isFalse);
      expect(SetType.superSet.countsAsVolume, isTrue);
      expect(SetType.superSet.drivesLoadProgression, isFalse);
      expect(SetType.working.drivesLoadProgression, isTrue);
    });
  });

  group('exercise history', () {
    LoggedSet set({
      required DateTime on,
      required double weight,
      required int reps,
      int index = 0,
      SetType type = SetType.working,
      Effort? effort,
    }) => LoggedSet(
      exerciseId: 'bench_press',
      setIndex: index,
      setType: type,
      weight: weight,
      unit: WeightUnit.lb,
      reps: reps,
      effort: effort,
      performedAt: on,
    );

    test('is empty for an exercise never performed', () {
      final history = ExerciseHistory.empty('bench_press');
      expect(history.isEmpty, isTrue);
      expect(history.sessions, isEmpty);
      expect(history.workingSessions, isEmpty);
    });

    test('groups sets by day and orders sessions oldest first', () {
      final history = ExerciseHistory(
        exerciseId: 'bench_press',
        sets: [
          set(on: DateTime(2026, 10, 8, 17), weight: 140, reps: 8),
          set(on: DateTime(2026, 10, 1, 17), weight: 135, reps: 8),
          set(on: DateTime(2026, 10, 1, 17, 5), weight: 135, reps: 7, index: 1),
        ],
      );

      expect(history.sessions, hasLength(2));
      expect(history.sessions.first.date, DateTime(2026, 10, 1));
      expect(history.sessions.first.sets, hasLength(2));
      expect(history.sessions.last.date, DateTime(2026, 10, 8));
    });

    test('reports the top working set and the fewest reps at that load', () {
      final history = ExerciseHistory(
        exerciseId: 'bench_press',
        sets: [
          set(
            on: DateTime(2026, 10, 1, 17),
            weight: 95,
            reps: 10,
            type: SetType.warmUp,
          ),
          set(
            on: DateTime(2026, 10, 1, 17, 5),
            weight: 135,
            reps: 12,
            index: 1,
          ),
          set(
            on: DateTime(2026, 10, 1, 17, 10),
            weight: 135,
            reps: 8,
            index: 2,
          ),
        ],
      );

      final session = history.sessions.single;
      expect(session.topWorkingLoadLb, 135);
      // 12 then 8 is not "12 reps at 135" - the conservative read is 8.
      expect(session.repsAtTopLoad, 8);
      expect(session.hardSetCount, 2, reason: 'the warm-up is not a hard set');
    });

    test('takes the hardest reported effort at the top load', () {
      final history = ExerciseHistory(
        exerciseId: 'bench_press',
        sets: [
          set(
            on: DateTime(2026, 10, 1, 17),
            weight: 135,
            reps: 8,
            effort: Effort.rpe(7),
          ),
          set(
            on: DateTime(2026, 10, 1, 17, 5),
            weight: 135,
            reps: 8,
            index: 1,
            effort: Effort.rpe(9),
          ),
        ],
      );

      expect(history.sessions.single.effortAtTopLoad, Effort.rpe(9));
    });

    test('ignores a session made only of warm-ups when progressing load', () {
      final history = ExerciseHistory(
        exerciseId: 'bench_press',
        sets: [
          set(
            on: DateTime(2026, 10, 1),
            weight: 45,
            reps: 10,
            type: SetType.warmUp,
          ),
        ],
      );

      expect(history.sessions, hasLength(1));
      expect(history.workingSessions, isEmpty);
    });

    test('refuses a set belonging to a different exercise', () {
      expect(
        () => ExerciseHistory(
          exerciseId: 'bench_press',
          sets: [
            LoggedSet(
              exerciseId: 'squat',
              setIndex: 0,
              setType: SetType.working,
              weight: 225,
              unit: WeightUnit.lb,
              reps: 5,
              performedAt: DateTime(2026, 10, 1),
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('a rep range', () {
    test('knows when the top was reached and when the bottom was missed', () {
      const hypertrophy = RepRange(8, 12);
      expect(hypertrophy.contains(10), isTrue);
      expect(hypertrophy.isAtOrAboveTop(12), isTrue);
      expect(hypertrophy.isAtOrAboveTop(11), isFalse);
      expect(hypertrophy.isBelowBottom(7), isTrue);
      expect(hypertrophy.toString(), '8-12');
      expect(RepRange.exactly(5).toString(), '5');
    });
  });
}
