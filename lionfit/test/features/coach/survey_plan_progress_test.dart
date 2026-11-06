import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/coach/domain/coach_engine.dart';
import 'package:lionfit/features/coach/domain/progress.dart';
import 'package:lionfit/features/coach/domain/starting_load.dart';
import 'package:lionfit/features/coach/domain/weekly_plan.dart';
import 'package:lionfit/features/onboarding/domain/survey.dart';
import 'package:lionfit/features/workout/domain/training_profile.dart';
import 'package:lionfit/features/workout/domain/workout_models.dart';

import 'fixtures.dart';

void main() {
  final byId = {for (final e in catalog) e.id: e};
  const benchBaseline = StrengthBaseline(
    exerciseId: 'bench',
    weight: 135,
    unit: WeightUnit.lb,
    reps: 8,
  );

  group('starting load estimator', () {
    test('an exact survey answer is used as-is', () {
      final est = StartingLoadEstimator(
        baselines: const [benchBaseline],
        catalog: byId,
        experience: TrainingExperience.intermediate,
      );
      final e = est.estimate(bench)!;
      // Epley: 135 * (1 + 8/30) = 171.
      expect(e.e1rmLb, closeTo(171, 0.5));
      expect(e.source, contains('135 lb × 8'));
    });

    test('a related lift is carried across, lighter for isolation work', () {
      final est = StartingLoadEstimator(
        baselines: const [benchBaseline],
        catalog: byId,
        experience: TrainingExperience.intermediate,
      );
      final e = est.estimate(legExtension)!;
      expect(e.e1rmLb, lessThan(171));
      expect(e.e1rmLb, greaterThan(20));
      expect(e.source, contains('Barbell Bench Press'));
    });

    test('no answers: bodyweight x standards x experience', () {
      final newer = StartingLoadEstimator(
        baselines: const [],
        catalog: byId,
        experience: TrainingExperience.beginner,
        bodyweightLb: 180,
      ).estimate(bench)!;
      final stronger = StartingLoadEstimator(
        baselines: const [],
        catalog: byId,
        experience: TrainingExperience.advanced,
        bodyweightLb: 180,
      ).estimate(bench)!;
      expect(newer.e1rmLb, closeTo(180 * 1.0 * 1.0 * 0.55, 0.01));
      expect(stronger.e1rmLb, greaterThan(newer.e1rmLb));
    });

    test('a brand-new lifter with no bodyweight gets no guess', () {
      final est = StartingLoadEstimator(
        baselines: const [],
        catalog: byId,
        experience: TrainingExperience.brandNew,
      );
      expect(est.estimate(bench), isNull);
    });

    test('cardio and bodyweight work are never estimated', () {
      final est = StartingLoadEstimator(
        baselines: const [benchBaseline],
        catalog: byId,
        experience: TrainingExperience.advanced,
        bodyweightLb: 200,
      );
      expect(est.estimate(treadmill), isNull);
      expect(est.estimate(pushUp), isNull);
    });

    test('the first working load is easy: at least 3 reps in reserve', () {
      final est = StartingLoadEstimator(
        baselines: const [benchBaseline],
        catalog: byId,
        experience: TrainingExperience.intermediate,
      );
      final load = est.firstWorkingLoadLb(
        bench,
        targetReps: const RepRange(8, 12),
      )!;
      // 12 reps + 3 in reserve off a 171 e1RM is about 114 - well under the
      // 135 the user can already do for 8.
      expect(load, lessThan(120));
      expect(load, greaterThan(100));
    });
  });

  group('coach engine with the survey', () {
    CoachEngine engine({
      List<SetRecord> history = const [],
      List<StrengthBaseline> baselines = const [],
      TrainingProfile profile = const TrainingProfile(),
    }) => CoachEngine(
      catalog: catalog,
      inventory: inventory,
      history: history,
      profile: profile,
      baselines: baselines,
    );

    test('no survey: first time still starts at the lightest setting', () {
      final s = engine().suggestFor(bench);
      expect(s.basis, SuggestionBasis.firstTime);
      expect(s.weight, 45);
    });

    test('with a survey answer: an estimated, real-plate first load', () {
      final s = engine(
        baselines: const [benchBaseline],
        profile: const TrainingProfile(
          experience: TrainingExperience.intermediate,
        ),
      ).suggestFor(bench);
      expect(s.basis, SuggestionBasis.estimated);
      expect(s.weight, greaterThan(45));
      expect(s.weight, lessThan(135));
      expect(s.weight! % 5, 0);
      expect(s.reason, contains('From your survey'));
    });

    test('after one easy, rated session the load goes up', () {
      final s = engine(
        history: [
          logged(bench, on: DateTime(2026, 10, 14), lb: 95, reps: 12, rpe: 6),
        ],
      ).suggestFor(bench);
      expect(s.basis, SuggestionBasis.calibrated);
      expect(s.weight, greaterThan(95));
      expect(s.weight, lessThanOrEqualTo(95 * 1.2));
      expect(s.reason, contains('RPE 6'));
    });

    test('after one grinding, rated session the load comes down', () {
      final s = engine(
        history: [
          logged(bench, on: DateTime(2026, 10, 14), lb: 135, reps: 6, rir: 0),
        ],
      ).suggestFor(bench);
      expect(s.basis, SuggestionBasis.calibrated);
      expect(s.weight, lessThan(135));
    });

    test('a survey answer newer than the history overrides it', () {
      final s = engine(
        history: [
          logged(bench, on: DateTime(2026, 10, 1), lb: 95, reps: 10),
          logged(bench, on: DateTime(2026, 10, 8), lb: 95, reps: 10),
        ],
        baselines: [
          StrengthBaseline(
            exerciseId: 'bench',
            weight: 185,
            unit: WeightUnit.lb,
            reps: 5,
            recordedAt: DateTime(2026, 11, 5),
          ),
        ],
        profile: const TrainingProfile(
          experience: TrainingExperience.intermediate,
        ),
      ).suggestFor(bench);
      expect(s.basis, SuggestionBasis.estimated);
      // e1RM ~216; 6-10 reps for general fitness -> 8 reps at 2 RIR ~ 162,
      // rounded down to real plates - far above the old 95.
      expect(s.weight, greaterThan(140));
      expect(s.reason, contains('newer than your last logged session'));
    });

    test('a session logged after the survey takes over again', () {
      final s = engine(
        history: [
          logged(bench, on: DateTime(2026, 11, 6), lb: 155, reps: 8, rpe: 8),
          logged(bench, on: DateTime(2026, 11, 9), lb: 155, reps: 9, rpe: 8),
        ],
        baselines: [
          StrengthBaseline(
            exerciseId: 'bench',
            weight: 185,
            unit: WeightUnit.lb,
            reps: 5,
            recordedAt: DateTime(2026, 11, 5),
          ),
        ],
      ).suggestFor(bench);
      expect(s.basis, SuggestionBasis.progression);
    });

    test("today's prescription ignores today's sets (before:)", () {
      final day = DateTime(2026, 10, 14);
      final e = engine(
        history: [
          logged(bench, on: DateTime(2026, 10, 7), lb: 135, reps: 9),
          logged(bench, on: day, lb: 155, reps: 12, rpe: 6),
        ],
      );
      final planned = e.suggestFor(bench, before: day);
      expect(planned.basis, SuggestionBasis.repeat);
      expect(planned.weight, 135);
      // Without the cut-off the same history reads as two sessions.
      expect(e.suggestFor(bench).basis, isNot(SuggestionBasis.repeat));
    });

    test('an unrated single session is still just repeated', () {
      final s = engine(
        history: [logged(bench, on: DateTime(2026, 10, 14), lb: 135, reps: 9)],
      ).suggestFor(bench);
      expect(s.basis, SuggestionBasis.repeat);
    });

    test('swap options share the muscle, skip the excluded, max three', () {
      final options = engine().swapOptionsFor(bench, excludeIds: {'bench'});
      expect(options, isNotEmpty);
      expect(options.length, lessThanOrEqualTo(3));
      for (final o in options) {
        expect(o.primaryMuscleGroups, contains(MuscleGroup.chestLower));
        expect(o.id, isNot('bench'));
      }
      expect(options.first.id, 'pushup');
    });

    test('cardio swaps only for other cardio', () {
      final options = engine().swapOptionsFor(treadmill);
      expect(options.map((e) => e.id), ['run']);
    });
  });

  group('weekly plan', () {
    final monday = DateTime(2026, 10, 19);

    test('no history: a calibration week of short days and two sets', () {
      final plan = generateWeeklyPlan(
        engine: CoachEngine(
          catalog: catalog,
          inventory: inventory,
          history: const [],
          profile: const TrainingProfile(
            daysPerWeek: 4,
            goal: TrainingGoal.muscleGain,
          ),
        ),
        asOf: monday,
      );
      expect(plan.isCalibration, isTrue);
      for (final day in plan.trainingDays) {
        final strength = day.exercises.where((s) => !s.exercise.isCardio);
        expect(strength.length, lessThanOrEqualTo(4));
        for (final s in strength) {
          expect(s.sets, lessThanOrEqualTo(2));
        }
      }
    });

    test('history from before the week: a normal week', () {
      final plan = generateWeeklyPlan(
        engine: CoachEngine(
          catalog: catalog,
          inventory: inventory,
          history: [
            logged(bench, on: DateTime(2026, 10, 12), lb: 135, reps: 8),
          ],
          profile: const TrainingProfile(goal: TrainingGoal.muscleGain),
        ),
        asOf: monday,
      );
      expect(plan.isCalibration, isFalse);
    });

    test('logging during the week does not reshuffle the plan', () {
      CoachEngine engineWith(List<SetRecord> history) => CoachEngine(
        catalog: catalog,
        inventory: inventory,
        history: history,
        profile: const TrainingProfile(daysPerWeek: 5),
      );
      List<String> ids(WeeklyPlan p) => [
        for (final d in p.days)
          for (final s in d.exercises) s.exercise.id,
      ];
      final before = generateWeeklyPlan(
        engine: engineWith(const []),
        asOf: monday,
      );
      final after = generateWeeklyPlan(
        engine: engineWith([
          logged(pushUp, on: monday, reps: 15),
          logged(legExtension, on: monday, lb: 50, reps: 12),
        ]),
        asOf: DateTime(2026, 10, 20),
      );
      expect(ids(after), ids(before));
    });

    test('a swap replaces the slot and remembers the original', () {
      final engine = CoachEngine(
        catalog: catalog,
        inventory: inventory,
        history: const [],
        profile: const TrainingProfile(daysPerWeek: 3),
      );
      final plan = generateWeeklyPlan(engine: engine, asOf: monday);
      final day = plan.dayFor(monday)!;
      final onDay = {for (final s in day.exercises) s.exercise.id};
      // The first slot that has an alternative in the small test catalog.
      final slot = day.exercises.indexWhere(
        (s) => engine.swapOptionsFor(s.exercise, excludeIds: onDay).isNotEmpty,
      );
      expect(slot, isNonNegative);
      final original = day.exercises[slot].exercise;
      final replacement = engine
          .swapOptionsFor(original, excludeIds: onDay)
          .first;

      final swapped = applySwaps(plan, [
        PlanSwap(
          planDate: monday,
          originalExerciseId: original.id,
          replacementExerciseId: replacement.id,
        ),
      ], engine: engine);
      final newDay = swapped.dayFor(monday)!;
      expect(newDay.exercises[slot].exercise.id, replacement.id);
      expect(newDay.replacedFrom[replacement.id]?.id, original.id);
      expect(newDay.exercises.length, day.exercises.length);
      // Other days untouched.
      expect(
        swapped.days.where((d) => d.replacedFrom.isNotEmpty),
        hasLength(1),
      );
    });
  });

  group('average progress', () {
    final mon = DateTime(2026, 10, 12);
    final thu = DateTime(2026, 10, 15);
    final nextMon = DateTime(2026, 10, 19);

    final sets = [
      logged(bench, on: mon, lb: 100, reps: 10),
      logged(bench, on: mon, lb: 120, reps: 8, index: 2),
      logged(bench, on: mon, lb: 45, reps: 10, index: 3, type: SetType.warmUp),
      logged(bench, on: thu, lb: 130, reps: 8),
      logged(bench, on: nextMon, lb: 125, reps: 8),
    ];

    test('averages working sets per day, warm-ups excluded', () {
      final p = averageProgress('bench', sets);
      expect(p.isLoaded, isTrue);
      expect(p.points.map((d) => d.value), [110, 130, 125]);
      expect(p.points.first.sets, 2);
      expect(p.points.first.averageReps, 9);
    });

    test('previous week is the whole prior Mon-Sun', () {
      final p = averageProgress('bench', sets);
      expect(p.previousWeek[0], isNull);
      expect(p.previousWeek[1], isNull);
      // (100 + 120 + 130) / 3
      expect(p.previousWeek[2], closeTo(116.67, 0.01));
      expect(
        p.changeVs(ProgressComparison.lastWeek),
        closeTo((125 - 116.67) / 116.67, 0.001),
      );
    });

    test('personal best runs forward and compares the latest', () {
      final p = averageProgress('bench', sets);
      expect(p.runningBest, [110, 130, 130]);
      expect(p.best!.value, 130);
      expect(
        p.changeVs(ProgressComparison.personalBest),
        closeTo((125 - 130) / 130, 0.0001),
      );
    });

    test('bodyweight work averages reps', () {
      final p = averageProgress('pushup', [
        logged(pushUp, on: mon, reps: 10),
        logged(pushUp, on: mon, reps: 14, index: 2),
      ]);
      expect(p.isLoaded, isFalse);
      expect(p.points.single.value, 12);
    });
  });

  group('survey options', () {
    test('only loaded lifts of the category, preferred first', () {
      final options = surveyOptions(catalog, kSurveyLiftCategories.first);
      expect(options.map((e) => e.id), ['bench']);
    });

    test('retired exercises are never offered', () {
      final squat = kSurveyLiftCategories[1];
      expect(surveyOptions(catalog, squat), isEmpty);
    });
  });
}
