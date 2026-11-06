import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/core/training/muscle_status.dart';
import 'package:lionfit/core/training/progression.dart';
import 'package:lionfit/features/coach/domain/coach_engine.dart';
import 'package:lionfit/features/workout/domain/training_profile.dart';

import 'fixtures.dart';

void main() {
  final today = DateTime(2026, 10, 19); // a Monday

  CoachEngine engineWith(
    List history, {
    TrainingProfile profile = const TrainingProfile(),
  }) => CoachEngine(
    catalog: catalog,
    inventory: inventory,
    history: history.cast(),
    profile: profile,
  );

  group('next load', () {
    test('first time on a machine: its lightest real setting', () {
      final s = engineWith([]).suggestFor(legExtension);
      expect(s.basis, SuggestionBasis.firstTime);
      expect(s.weight, 12.5);
      expect(s.equipmentLabel, 'Leg Extension');
    });

    test('first time on a barbell station starts at the empty bar', () {
      final s = engineWith([]).suggestFor(bench);
      expect(s.weight, 45);
    });

    test('one session logged: repeat it', () {
      final s = engineWith([
        logged(bench, on: DateTime(2026, 10, 14), lb: 135, reps: 9),
      ]).suggestFor(bench);
      expect(s.basis, SuggestionBasis.repeat);
      expect(s.weight, 135);
      expect(s.reps, 9);
    });

    test(
      'hit the top of the range comfortably twice: go up, on real plates',
      () {
        final s = engineWith([
          logged(bench, on: DateTime(2026, 10, 7), lb: 135, reps: 12, rir: 3),
          logged(bench, on: DateTime(2026, 10, 14), lb: 135, reps: 12, rir: 3),
        ]).suggestFor(bench);
        expect(s.basis, SuggestionBasis.progression);
        expect(s.action, ProgressionAction.increase);
        expect(s.weight, greaterThan(135));
        // 10% cap and a 5 lb smallest jump.
        expect(s.weight, lessThanOrEqualTo(148.5));
        expect(s.weight! % 5, 0);
        expect(s.reps, s.targetReps.min);
      },
    );

    test('missed the bottom of the range: back off', () {
      final s = engineWith([
        logged(bench, on: DateTime(2026, 10, 7), lb: 135, reps: 8, rpe: 9),
        logged(bench, on: DateTime(2026, 10, 14), lb: 135, reps: 5, rpe: 10),
      ]).suggestFor(bench);
      expect(s.action, ProgressionAction.reduce);
      expect(s.weight, lessThan(135));
    });

    test('leg extension suggestions land on 12.5 lb pins', () {
      final s = engineWith([
        logged(
          legExtension,
          on: DateTime(2026, 10, 7),
          lb: 100,
          reps: 15,
          rir: 4,
        ),
        logged(
          legExtension,
          on: DateTime(2026, 10, 14),
          lb: 100,
          reps: 15,
          rir: 4,
        ),
      ]).suggestFor(legExtension);
      expect(s.weight! % 12.5, 0);
    });

    test('kg users get the same physical load, converted', () {
      final s = engineWith([
        logged(bench, on: DateTime(2026, 10, 14), lb: 135, reps: 9),
      ], profile: const TrainingProfile(unit: WeightUnit.kg)).suggestFor(bench);
      expect(s.unit, WeightUnit.kg);
      expect(s.weight, closeTo(61.0, 0.3));
    });

    test('bodyweight progresses by reps', () {
      final s = engineWith([
        logged(pushUp, on: DateTime(2026, 10, 14), reps: 15),
      ]).suggestFor(pushUp);
      expect(s.basis, SuggestionBasis.bodyweight);
      expect(s.weight, isNull);
      expect(s.reps, 16);
    });

    test('cardio is minutes, one block', () {
      final s = engineWith(
        [],
        profile: const TrainingProfile(goal: TrainingGoal.weightLoss),
      ).suggestFor(treadmill);
      expect(s.basis, SuggestionBasis.cardio);
      expect(s.reps, 30);
      expect(s.sets, 1);
    });
  });

  group('availability', () {
    test(
      'out-of-service equipment and retired exercises are never offered',
      () {
        final engine = engineWith([]);
        expect(engine.isAvailable(seatedCalf), isFalse);
        expect(engine.isAvailable(retiredSquat), isFalse);
        expect(engine.candidatesFor(MuscleGroup.calves).map((e) => e.id), [
          'calf',
        ]);
      },
    );

    test('exercises the user has done rank first', () {
      final engine = engineWith([
        logged(pushUp, on: DateTime(2026, 10, 14), reps: 12),
      ]);
      expect(engine.candidatesFor(MuscleGroup.chestLower).first.id, 'pushup');
    });
  });

  group('brief', () {
    test('untrained muscles come first, each with loggable suggestions', () {
      final engine = engineWith([
        for (var i = 1; i <= 4; i++)
          logged(
            bench,
            on: DateTime(2026, 10, 18),
            lb: 135,
            reps: 10,
            index: i,
          ),
      ]);
      final brief = engine.brief(asOf: today);
      expect(brief.nextLoads.map((s) => s.exercise.id), ['bench']);
      expect(brief.muscleGaps.first.status, MuscleTrainingStatus.untrained);
      final calves = brief.muscleGaps.firstWhere(
        (g) => g.group == MuscleGroup.calves,
        orElse: () => throw StateError('calves missing'),
      );
      expect(calves.suggestions.single.exercise.id, 'calf');
    });

    test('the JSON sent to the Edge Function carries no free text', () {
      final engine = engineWith([
        logged(bench, on: DateTime(2026, 10, 18), lb: 135, reps: 10),
      ]);
      final json = engine.brief(asOf: today, maxGaps: 16).toJson();
      final load = (json['next_loads'] as List).single as Map;
      expect(load.keys, isNot(contains('name')));
      expect(load.keys, isNot(contains('reason')));
      expect(load['exercise_slug'], 'barbell_bench_press');
      for (final gap in json['muscle_gaps'] as List) {
        for (final slug in (gap as Map)['candidate_slugs'] as List) {
          expect(slug, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
        }
      }
    });
  });

  test('rep ranges follow movement and goal', () {
    expect(
      targetRepsFor(bench, TrainingGoal.muscleGain),
      const RepRange(6, 10),
    );
    expect(
      targetRepsFor(legExtension, TrainingGoal.weightLoss),
      const RepRange(12, 20),
    );
  });
}
