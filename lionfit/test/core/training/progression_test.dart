// What the engine tells a lifter to load next, and the guardrails that stop it
// from telling them something silly. Scenario by scenario, the way a user would
// hit them.
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/load_quantization.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/core/training/progression.dart';

void main() {
  final engine = ProgressionEngine();

  LoggedSet lift({
    required DateTime on,
    required double lb,
    required int reps,
    Effort? effort,
    int index = 0,
    SetType type = SetType.working,
    String exerciseId = 'bench_press',
    WeightUnit unit = WeightUnit.lb,
  }) => LoggedSet(
    exerciseId: exerciseId,
    setIndex: index,
    setType: type,
    weight: lb,
    unit: unit,
    reps: reps,
    effort: effort,
    performedAt: on,
  );

  ExerciseHistory historyOf(
    List<LoggedSet> sets, {
    String exerciseId = 'bench_press',
  }) => ExerciseHistory(exerciseId: exerciseId, sets: sets);

  group('a lifter with almost no history', () {
    test('gets no load suggestion at all on a first-ever session', () {
      final outcome = engine.recommend(
        history: ExerciseHistory.empty('bench_press'),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      expect(outcome, isA<NotEnoughData>());
      final sparse = outcome as NotEnoughData;
      expect(sparse.sessionsLogged, 0);
      expect(sparse.repeatLoadLb, isNull);
      expect(sparse.reason, contains('first time'));
    });

    test('is told one session is not a trend, and what to repeat', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 10,
            effort: Effort.rpe(7),
          ),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      expect(outcome, isA<NotEnoughData>());
      final sparse = outcome as NotEnoughData;
      expect(sparse.sessionsLogged, 1);
      expect(sparse.sessionsRequired, 2);
      expect(sparse.repeatLoadLb, 135);
      expect(sparse.reason, contains('135 lb'));
    });

    test('never gets a number extrapolated from a single data point', () {
      // The outcome type forces the caller to deal with it - there is no
      // nullable double to quietly render as blank.
      final outcome = engine.recommend(
        history: historyOf([
          lift(on: DateTime(2026, 10, 1), lb: 135, reps: 10),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      final rendered = switch (outcome) {
        NotEnoughData() => 'keep logging',
        LoadSuggestion(:final suggestedLoadLb) => 'load $suggestedLoadLb',
      };
      expect(rendered, 'keep logging');
    });

    test('counts only sessions that contained a real working set', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 45,
            reps: 10,
            type: SetType.warmUp,
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 10,
            effort: Effort.rpe(7),
          ),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      expect(outcome, isA<NotEnoughData>());
      expect((outcome as NotEnoughData).sessionsLogged, 1);
    });
  });

  group('double progression', () {
    test('hitting the top of the range at RPE 7 earns the next weight up', () {
      // The worked example from CLAUDE.md: 135 x 10, first and last rep felt
      // about the same, so there are reps left - try 145.
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 10,
            effort: Effort.rpe(7),
          ),
        ]),
        targetReps: const RepRange(8, 10),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.increase);
      expect(suggestion.suggestedLoadLb, 145);
      expect(suggestion.previousLoadLb, 135);
      expect(suggestion.effortWasMissing, isFalse);
      expect(
        suggestion.reason,
        'You hit 10 reps at RPE 7, roughly 3 reps left in the tank - '
        'try 145 lb.',
      );
    });

    test('landing mid-range keeps the weight and asks for another rep', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 9,
            effort: Effort.rpe(8),
          ),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.hold);
      expect(suggestion.suggestedLoadLb, 135);
      expect(suggestion.reason, contains('add reps'));
    });

    test('a drop set after the working sets does not drag the load down', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 10,
            effort: Effort.rpe(7),
          ),
          lift(
            on: DateTime(2026, 10, 8, 17, 30),
            lb: 95,
            reps: 12,
            index: 1,
            type: SetType.dropSet,
            effort: Effort.rpe(9),
          ),
        ]),
        targetReps: const RepRange(8, 10),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.previousLoadLb, 135);
      expect(suggestion.suggestedLoadLb, 145);
    });
  });

  group('a missed target', () {
    test('backs the load off instead of asking for the same weight again', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 185,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 185,
            reps: 4,
            effort: Effort.rpe(10),
          ),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.reduce);
      // The estimate wanted 157; 10% is the most we move, and 165 would have
      // been 10.8% - so the first real weight at or above the floor it is.
      expect(suggestion.suggestedLoadLb, 170);
      expect(suggestion.suggestedLoadLb, lessThan(suggestion.previousLoadLb));
      expect(
        suggestion.cappedByGuardrail,
        isTrue,
        reason: 'the estimate wanted to drop further than 10%',
      );
      expect(suggestion.changeFraction, greaterThanOrEqualTo(-0.10));
      expect(suggestion.reason, contains('170 lb'));
    });

    test('a failed set with zero reps still produces a usable answer', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 185,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 185,
            reps: 8,
            effort: Effort.rpe(9),
          ),
          lift(
            on: DateTime(2026, 10, 15),
            lb: 185,
            reps: 0,
            effort: Effort.rpe(10),
          ),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(
        suggestion.action,
        anyOf(ProgressionAction.reduce, ProgressionAction.deload),
      );
      expect(suggestion.suggestedLoadLb, lessThan(185));
      expect(suggestion.changeFraction, greaterThanOrEqualTo(-0.10 - 1e-9));
    });

    test('one rep short with reps still in the tank runs the weight back', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rir(2),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 7,
            effort: Effort.rir(4),
          ),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.hold);
      expect(suggestion.suggestedLoadLb, 135);
      expect(suggestion.reason, contains('same weight back'));
    });

    test('never turns into an increase, whatever the estimate says', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rir(2),
          ),
          // Stopped early with plenty left: the e1RM math alone would ask for
          // more weight. A missed target must not do that.
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 6,
            effort: Effort.rir(5),
          ),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(
        suggestion.rawTargetLoadLb,
        greaterThan(135),
        reason: 'the raw math really did want to go up',
      );
      expect(suggestion.suggestedLoadLb, lessThanOrEqualTo(135));
    });
  });

  group('a set with no RPE and no RIR', () {
    test('earns only the smallest real step up', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(on: DateTime(2026, 10, 1), lb: 135, reps: 8),
          lift(on: DateTime(2026, 10, 8), lb: 135, reps: 10),
        ]),
        targetReps: const RepRange(8, 10),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.increase);
      expect(suggestion.effortWasMissing, isTrue);
      expect(
        suggestion.suggestedLoadLb,
        140,
        reason: 'one 2.5 lb plate per side, not the 145 a rated set earns',
      );
      expect(suggestion.reason, contains('without logging an RPE'));
    });

    test('is still judged against the rep range, not ignored', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(on: DateTime(2026, 10, 1), lb: 135, reps: 8),
          lift(on: DateTime(2026, 10, 8), lb: 135, reps: 5),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.reduce);
      expect(suggestion.effortWasMissing, isTrue);
    });
  });

  group('the 10% guardrail', () {
    test('caps a jump the math wanted to make much bigger', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 225,
            reps: 8,
            effort: Effort.rir(4),
            exerciseId: 'back_squat',
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 225,
            reps: 10,
            effort: Effort.rir(4),
            exerciseId: 'back_squat',
          ),
        ], exerciseId: 'back_squat'),
        targetReps: const RepRange(5, 8),
        equipment: EquipmentType.squatRack,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.increase);
      expect(
        suggestion.rawTargetLoadLb,
        greaterThan(260),
        reason: 'ten reps with four in reserve really does imply a lot more',
      );
      expect(suggestion.cappedByGuardrail, isTrue);
      expect(suggestion.suggestedLoadLb, 245);
      expect(suggestion.changeFraction, lessThanOrEqualTo(0.10));
      expect(suggestion.reason, contains('10%'));
    });

    test('is not smuggled past by rounding up to the next real weight', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 10,
            effort: Effort.rpe(7),
          ),
        ]),
        targetReps: const RepRange(8, 10),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      // Rounding a comfortable set up would reach 150, which is 11.1%.
      expect(suggestion.suggestedLoadLb, 145);
      expect(suggestion.changeFraction, lessThanOrEqualTo(0.10));
    });

    test('holds a light dumbbell rather than doubling the load', () {
      // The rack goes 10 -> 15: a 50% jump. 10% of 10 lb does not exist.
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 10,
            reps: 12,
            effort: Effort.rir(3),
            exerciseId: 'lateral_raise',
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 10,
            reps: 12,
            effort: Effort.rir(4),
            exerciseId: 'lateral_raise',
          ),
        ], exerciseId: 'lateral_raise'),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.dumbbell,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.hold);
      expect(suggestion.blockedByEquipmentStep, isTrue);
      expect(suggestion.suggestedLoadLb, 10);
      expect(suggestion.reason, contains('add reps'));
    });

    test(
      'allows the one documented exception when the estimate supports it',
      () {
        // Same rack, but this lifter is now doing 25 reps with 5 still in the
        // tank: the next dumbbell up is a big jump and they have clearly earned
        // it. Holding forever would be the wrong answer.
        final outcome = engine.recommend(
          history: historyOf([
            lift(
              on: DateTime(2026, 10, 1),
              lb: 10,
              reps: 20,
              effort: Effort.rir(4),
              exerciseId: 'lateral_raise',
            ),
            lift(
              on: DateTime(2026, 10, 8),
              lb: 10,
              reps: 25,
              effort: Effort.rir(5),
              exerciseId: 'lateral_raise',
            ),
          ], exerciseId: 'lateral_raise'),
          targetReps: const RepRange(8, 12),
          equipment: EquipmentType.dumbbell,
        );

        final suggestion = outcome as LoadSuggestion;
        expect(suggestion.action, ProgressionAction.increase);
        expect(suggestion.suggestedLoadLb, 15);
        expect(suggestion.exceededGuardrailForSmallestStep, isTrue);
        expect(suggestion.reason, contains('smallest this equipment has'));
      },
    );
  });

  group('accumulated fatigue', () {
    test('holds when RPE climbs while the reps stay flat', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(7),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 15),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(9),
          ),
        ]),
        // 8 reps is the top of this range, so without the fatigue check this
        // would be a straight increase.
        targetReps: const RepRange(5, 8),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.hold);
      expect(
        suggestion.fatigueSignal,
        FatigueSignal.effortRisingPerformanceFlat,
      );
      expect(suggestion.suggestedLoadLb, 135);
      expect(suggestion.reason, contains('RPE 7 to RPE 9'));
      expect(suggestion.reason, contains('fatigue'));
    });

    test('deloads when RPE climbs while the reps fall away', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 7,
            effort: Effort.rpe(9),
          ),
          lift(
            on: DateTime(2026, 10, 15),
            lb: 135,
            reps: 6,
            effort: Effort.rpe(10),
          ),
        ]),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.action, ProgressionAction.deload);
      expect(suggestion.fatigueSignal, FatigueSignal.performanceDeclining);
      expect(suggestion.suggestedLoadLb, 125);
      expect(suggestion.changeFraction, greaterThanOrEqualTo(-0.10));
      expect(suggestion.reason, contains('lighter week'));
    });

    test('does not cry fatigue when the lifter is simply getting stronger', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(7),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 145,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 15),
            lb: 155,
            reps: 8,
            effort: Effort.rpe(9),
          ),
        ]),
        targetReps: const RepRange(5, 8),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.fatigueSignal, FatigueSignal.none);
      expect(suggestion.action, ProgressionAction.increase);
    });

    test('says nothing about fatigue when the sessions were never rated', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(on: DateTime(2026, 10, 1), lb: 135, reps: 8),
          lift(on: DateTime(2026, 10, 8), lb: 135, reps: 8),
          lift(on: DateTime(2026, 10, 15), lb: 135, reps: 8),
        ]),
        targetReps: const RepRange(5, 8),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.fatigueSignal, FatigueSignal.none);
      expect(suggestion.effortWasMissing, isTrue);
    });
  });

  group('units and equipment', () {
    test('gives a kilogram user the same bar with a converted label', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 10,
            effort: Effort.rpe(7),
          ),
        ]),
        targetReps: const RepRange(8, 10),
        equipment: EquipmentType.benchPress,
        displayUnit: WeightUnit.kg,
      );

      final suggestion = outcome as LoadSuggestion;
      // Same physical bar - quantization happens in the unit the plates are
      // labelled in.
      expect(suggestion.suggestedLoadLb, 145);
      expect(suggestion.suggestedLoad.unit, WeightUnit.kg);
      expect(suggestion.suggestedLoad.value, closeTo(65.8, 0.05));
      expect(suggestion.reason, contains('65.8 kg'));
    });

    test('reads a history logged in kilograms', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 60,
            reps: 8,
            unit: WeightUnit.kg,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 60,
            reps: 10,
            unit: WeightUnit.kg,
            effort: Effort.rpe(7),
          ),
        ]),
        targetReps: const RepRange(8, 10),
        equipment: EquipmentType.benchPress,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.previousLoadLb, closeTo(132.277, 0.001));
      expect(
        suggestion.suggestedLoadLb,
        145,
        reason:
            '60 kg is 132.3 lb, which is not a load any bar can hold - '
            'the suggestion is a weight that can actually be built',
      );
    });

    test('snaps to the machine stack when the exercise is a machine', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 100,
            reps: 10,
            effort: Effort.rpe(8),
            exerciseId: 'lat_pulldown',
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 100,
            reps: 12,
            effort: Effort.rpe(7),
            exerciseId: 'lat_pulldown',
          ),
        ], exerciseId: 'lat_pulldown'),
        targetReps: const RepRange(8, 12),
        equipment: EquipmentType.latPulldown,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(
        suggestion.suggestedLoadLb % 10,
        0,
        reason: 'the assumed pin spacing is 10 lb',
      );
      expect(suggestion.usesUnverifiedEquipmentData, isTrue);
      expect(suggestion.equipmentDescription, contains('ASSUMED'));
    });

    test('honours an injected quantizer over the registry default', () {
      final outcome = engine.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 10,
            effort: Effort.rpe(7),
          ),
        ]),
        targetReps: const RepRange(8, 10),
        equipment: EquipmentType.benchPress,
        quantizer: BarbellQuantizer(
          plateDenominationsLb: const [45, 25, 10, 5],
          denominationsAreVerified: true,
        ),
      );

      final suggestion = outcome as LoadSuggestion;
      // Without 2.5 lb plates the only loads near the target are 135 and 145.
      expect(suggestion.suggestedLoadLb, 145);
      expect(suggestion.usesUnverifiedEquipmentData, isFalse);
    });
  });

  group('configuration', () {
    test('lets a coach tighten the guardrail without touching the math', () {
      final cautious = ProgressionEngine(
        config: const ProgressionConfig(maxSessionChangeFraction: 0.02),
      );
      final outcome = cautious.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 225,
            reps: 8,
            effort: Effort.rir(4),
            exerciseId: 'back_squat',
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 225,
            reps: 10,
            effort: Effort.rir(4),
            exerciseId: 'back_squat',
          ),
        ], exerciseId: 'back_squat'),
        targetReps: const RepRange(5, 8),
        equipment: EquipmentType.squatRack,
      );

      final suggestion = outcome as LoadSuggestion;
      expect(suggestion.cappedByGuardrail, isTrue);
      // 2% of 225 is 4.5 lb and the smallest plate pair is 5, so this falls to
      // the documented exception: exactly one step, flagged as such, instead of
      // the 267 lb the math asked for.
      expect(suggestion.suggestedLoadLb, 230);
      expect(suggestion.exceededGuardrailForSmallestStep, isTrue);
    });

    test('lets a coach demand more history before suggesting anything', () {
      final patient = ProgressionEngine(
        config: const ProgressionConfig(minSessionsForSuggestion: 4),
      );
      final outcome = patient.recommend(
        history: historyOf([
          lift(
            on: DateTime(2026, 10, 1),
            lb: 135,
            reps: 8,
            effort: Effort.rpe(8),
          ),
          lift(
            on: DateTime(2026, 10, 8),
            lb: 135,
            reps: 10,
            effort: Effort.rpe(7),
          ),
        ]),
        targetReps: const RepRange(8, 10),
        equipment: EquipmentType.benchPress,
      );

      expect(outcome, isA<NotEnoughData>());
      expect((outcome as NotEnoughData).sessionsRequired, 4);
    });
  });
}
