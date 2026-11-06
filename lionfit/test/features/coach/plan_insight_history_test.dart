import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/coach/domain/coach_engine.dart';
import 'package:lionfit/features/coach/domain/muscle_insight.dart';
import 'package:lionfit/features/coach/domain/progress.dart';
import 'package:lionfit/features/coach/domain/weekly_plan.dart';
import 'package:lionfit/features/history/domain/history_filter.dart';
import 'package:lionfit/features/workout/domain/training_profile.dart';

import 'fixtures.dart';

void main() {
  final byId = {for (final e in catalog) e.id: e};

  group('weekly plan', () {
    CoachEngine engine(int days, TrainingGoal goal) => CoachEngine(
      catalog: catalog,
      inventory: inventory,
      history: const [],
      profile: TrainingProfile(daysPerWeek: days, goal: goal),
    );

    test('seven days, Monday first, training days spread for 3/week', () {
      final plan = generateWeeklyPlan(
        engine: engine(3, TrainingGoal.generalFitness),
        asOf: DateTime(2026, 10, 22),
      );
      expect(plan.days, hasLength(7));
      expect(plan.weekStart, DateTime(2026, 10, 19));
      expect(
        [
          for (final d in plan.days)
            if (!d.isRest) d.date.weekday,
        ],
        [1, 3, 5],
      );
      expect(plan.days.first.kind, PlanDayKind.fullBodyA);
    });

    for (final days in [3, 4, 5, 6, 7]) {
      test('$days days/week gives $days training days', () {
        final plan = generateWeeklyPlan(
          engine: engine(days, TrainingGoal.muscleGain),
          asOf: DateTime(2026, 10, 19),
        );
        expect(plan.trainingDays, hasLength(days));
      });
    }

    test('never plans unavailable equipment or retired exercises', () {
      final plan = generateWeeklyPlan(
        engine: engine(6, TrainingGoal.weightLoss),
        asOf: DateTime(2026, 10, 19),
      );
      final ids = {
        for (final d in plan.days)
          for (final s in d.exercises) s.exercise.id,
      };
      expect(ids, isNot(contains('scalf')));
      expect(ids, isNot(contains('squat')));
    });

    test('weight loss finishes every training day with cardio', () {
      final plan = generateWeeklyPlan(
        engine: engine(3, TrainingGoal.weightLoss),
        asOf: DateTime(2026, 10, 19),
      );
      for (final day in plan.trainingDays) {
        expect(day.exercises.last.exercise.isCardio, isTrue);
      }
    });

    test('the same week always produces the same plan', () {
      final a = generateWeeklyPlan(
        engine: engine(4, TrainingGoal.muscleGain),
        asOf: DateTime(2026, 10, 19),
      );
      final b = generateWeeklyPlan(
        engine: engine(4, TrainingGoal.muscleGain),
        asOf: DateTime(2026, 10, 25),
      );
      expect(
        [
          for (final d in a.days)
            for (final s in d.exercises) s.exercise.id,
        ],
        [
          for (final d in b.days)
            for (final s in d.exercises) s.exercise.id,
        ],
      );
    });
  });

  group('muscle insight', () {
    final sets = [
      logged(bench, on: DateTime(2026, 10, 13), lb: 135, reps: 8),
      logged(bench, on: DateTime(2026, 10, 16), lb: 145, reps: 8, index: 1),
      logged(
        bench,
        on: DateTime(2026, 10, 16),
        lb: 95,
        reps: 10,
        index: 2,
        type: SetType.warmUp,
      ),
      logged(cableRow, on: DateTime(2026, 10, 15), lb: 100, reps: 10),
    ];

    test('chest work is direct; triceps on bench press is assisted', () {
      final chest = muscleInsight(
        group: MuscleGroup.chestLower,
        sets: sets,
        exercisesById: byId,
        windowDays: 7,
      );
      expect(chest.contributions.single.role, MuscleRole.direct);
      // Warm-up excluded.
      expect(chest.directSets, 2);
      expect(chest.contributions.single.bestSet!.weight, 145);
      expect(chest.contributions.single.trend, greaterThan(0));

      final triceps = muscleInsight(
        group: MuscleGroup.triceps,
        sets: sets,
        exercisesById: byId,
        windowDays: 7,
      );
      expect(triceps.contributions.single.role, MuscleRole.assisted);
      expect(triceps.directSets, 0);
      expect(triceps.headline, contains('Only indirect work'));
    });

    test('rows reach the lats both directly and through the rhomboids', () {
      final lats = muscleInsight(
        group: MuscleGroup.lats,
        sets: sets,
        exercisesById: byId,
        windowDays: 7,
      );
      expect(lats.contributions.single.role, MuscleRole.direct);
    });

    test('nothing logged reads as nothing', () {
      final calves = muscleInsight(
        group: MuscleGroup.calves,
        sets: sets,
        exercisesById: byId,
        windowDays: 7,
      );
      expect(calves.isEmpty, isTrue);
    });
  });

  group('history filter', () {
    final today = DateTime(2026, 10, 22); // Thursday
    final sets = [
      logged(bench, on: DateTime(2026, 10, 22), lb: 135, reps: 8),
      logged(rotaryCalf, on: DateTime(2026, 10, 20), lb: 100, reps: 12),
      logged(bench, on: DateTime(2026, 10, 14), lb: 130, reps: 8),
      logged(bench, on: DateTime(2026, 9, 29), lb: 125, reps: 8),
    ];

    test('opens on the last 7 days', () {
      const filter = HistoryFilter();
      expect(filter.range, const RecentDays(7));
      final days = applyHistoryFilter(
        sets: sets,
        exercisesById: byId,
        filter: filter,
        asOf: today,
      );
      expect(days.map((d) => d.day), [
        DateTime(2026, 10, 22),
        DateTime(2026, 10, 20),
      ]);
    });

    test('the slider narrows within the week', () {
      final days = applyHistoryFilter(
        sets: sets,
        exercisesById: byId,
        filter: const HistoryFilter(range: RecentDays(1)),
        asOf: today,
      );
      expect(days.single.day, DateTime(2026, 10, 22));
    });

    test('calendar weeks go back Monday to Sunday', () {
      expect(const CalendarWeek(1).bounds(today), (
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 18),
      ));
      final days = applyHistoryFilter(
        sets: sets,
        exercisesById: byId,
        filter: const HistoryFilter(range: CalendarWeek(3)),
        asOf: today,
      );
      expect(days.single.day, DateTime(2026, 9, 29));
      expect(const CalendarWeek(3).label(today), 'Week of Sep 28');
    });

    test('a muscle filter includes assisting exercises', () {
      final days = applyHistoryFilter(
        sets: sets,
        exercisesById: byId,
        filter: const HistoryFilter(muscle: MuscleGroup.triceps),
        asOf: today,
      );
      expect(days.single.entries.single.exercise.id, 'bench');
    });
  });

  group('progress', () {
    test('loaded lifts plot best e1RM per day', () {
      final p = exerciseProgress('bench', [
        logged(bench, on: DateTime(2026, 10, 7), lb: 135, reps: 8),
        logged(bench, on: DateTime(2026, 10, 7), lb: 125, reps: 8, index: 2),
        logged(bench, on: DateTime(2026, 10, 14), lb: 145, reps: 8),
      ]);
      expect(p.metric, ProgressMetric.e1rm);
      expect(p.points, hasLength(2));
      expect(p.change, greaterThan(0));
    });

    test('bodyweight plots reps', () {
      final p = exerciseProgress('pushup', [
        logged(pushUp, on: DateTime(2026, 10, 7), reps: 12),
        logged(pushUp, on: DateTime(2026, 10, 14), reps: 15),
      ]);
      expect(p.metric, ProgressMetric.reps);
      expect(p.points.last.value, 15);
    });

    test('this week vs last week', () {
      final c = compareWeeks([
        logged(bench, on: DateTime(2026, 10, 20), lb: 100, reps: 10),
        logged(bench, on: DateTime(2026, 10, 14), lb: 100, reps: 10),
        logged(bench, on: DateTime(2026, 10, 15), lb: 100, reps: 10),
      ], asOf: DateTime(2026, 10, 22));
      expect(c.thisWeekSets, 1);
      expect(c.lastWeekSets, 2);
      expect(c.thisWeekVolumeLb, 1000);
    });
  });
}
