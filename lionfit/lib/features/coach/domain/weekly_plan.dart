/// This week's plan: which days to train, what each day is, and the
/// exercises on it - built from the user's goal, days per week, the equipment
/// on the floor, and their own history.
///
/// ## Rules
///
/// * **3-7 days.** The split follows the count: 3 = full body A/B/C, 4 =
///   upper/lower x2, 5 = push/pull/legs/upper/lower, 6 = PPL x2, 7 = PPL x2 +
///   an outdoor conditioning day.
/// * **Only equipment that is on the floor.** Every exercise comes from
///   [CoachEngine.candidatesFor], which filters by availability.
/// * **Variation without chaos.** The first two slots of a day (the main
///   lifts) change every two weeks; the accessories change every week. Same
///   week in, same plan out - it is a pure function of the week number, so
///   reopening the app never reshuffles it.
/// * **Indoor and outdoor.** Weight-loss plans finish every day with cardio;
///   general fitness finishes the lower-body days with it. The finisher
///   alternates between Rec Center cardio machines and outdoor work.
///
/// * **Stable within the week.** Exercise choice ranks by history logged
///   *before* the week began, so logging Monday never reshuffles Wednesday.
/// * **A calibration week for new lifters.** With nothing logged before the
///   week, every day is shorter (four lifts), two sets each, at the top of
///   the rep range and deliberately light. Each rated set then sets the next
///   load (`CoachEngine.suggestFor`).
///
/// The plan itself is not persisted - it is recomputed from the week number.
/// Only the user's swaps are stored (`user_plan_swaps`), and [applySwaps]
/// lays them over the computed plan.
///
/// Pure Dart.
library;

import '../../../core/training/models.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/domain/workout_models.dart';
import 'coach_engine.dart';

enum PlanDayKind {
  fullBodyA('Full body A'),
  fullBodyB('Full body B'),
  fullBodyC('Full body C'),
  upper('Upper body'),
  lower('Lower body'),
  push('Push'),
  pull('Pull'),
  legs('Legs'),
  conditioning('Outdoor conditioning');

  const PlanDayKind(this.label);

  final String label;
}

const _slots = <PlanDayKind, List<MuscleGroup>>{
  PlanDayKind.fullBodyA: [
    MuscleGroup.quads,
    MuscleGroup.chestLower,
    MuscleGroup.lats,
    MuscleGroup.deltsSide,
    MuscleGroup.abs,
  ],
  PlanDayKind.fullBodyB: [
    MuscleGroup.hamstrings,
    MuscleGroup.chestUpper,
    MuscleGroup.lats,
    MuscleGroup.deltsRear,
    MuscleGroup.calves,
  ],
  PlanDayKind.fullBodyC: [
    MuscleGroup.glutes,
    MuscleGroup.deltsFront,
    MuscleGroup.lats,
    MuscleGroup.biceps,
    MuscleGroup.triceps,
  ],
  PlanDayKind.upper: [
    MuscleGroup.chestLower,
    MuscleGroup.lats,
    MuscleGroup.deltsFront,
    MuscleGroup.chestUpper,
    MuscleGroup.biceps,
    MuscleGroup.triceps,
  ],
  PlanDayKind.lower: [
    MuscleGroup.quads,
    MuscleGroup.hamstrings,
    MuscleGroup.glutes,
    MuscleGroup.adductors,
    MuscleGroup.calves,
    MuscleGroup.abs,
  ],
  PlanDayKind.push: [
    MuscleGroup.chestLower,
    MuscleGroup.deltsFront,
    MuscleGroup.chestUpper,
    MuscleGroup.deltsSide,
    MuscleGroup.triceps,
  ],
  PlanDayKind.pull: [
    MuscleGroup.lats,
    MuscleGroup.lats,
    MuscleGroup.deltsRear,
    MuscleGroup.trapsUpper,
    MuscleGroup.biceps,
    MuscleGroup.forearms,
  ],
  PlanDayKind.legs: [
    MuscleGroup.quads,
    MuscleGroup.hamstrings,
    MuscleGroup.glutes,
    MuscleGroup.calves,
    MuscleGroup.abs,
  ],
  PlanDayKind.conditioning: [MuscleGroup.abs],
};

/// Weekdays (1 = Monday) each frequency trains on: spread out, rest between.
const _trainingWeekdays = <int, List<int>>{
  3: [1, 3, 5],
  4: [1, 2, 4, 5],
  5: [1, 2, 3, 4, 5],
  6: [1, 2, 3, 4, 5, 6],
  7: [1, 2, 3, 4, 5, 6, 7],
};

const _splits = <int, List<PlanDayKind>>{
  3: [PlanDayKind.fullBodyA, PlanDayKind.fullBodyB, PlanDayKind.fullBodyC],
  4: [
    PlanDayKind.upper,
    PlanDayKind.lower,
    PlanDayKind.upper,
    PlanDayKind.lower,
  ],
  5: [
    PlanDayKind.push,
    PlanDayKind.pull,
    PlanDayKind.legs,
    PlanDayKind.upper,
    PlanDayKind.lower,
  ],
  6: [
    PlanDayKind.push,
    PlanDayKind.pull,
    PlanDayKind.legs,
    PlanDayKind.push,
    PlanDayKind.pull,
    PlanDayKind.legs,
  ],
  7: [
    PlanDayKind.push,
    PlanDayKind.pull,
    PlanDayKind.legs,
    PlanDayKind.push,
    PlanDayKind.pull,
    PlanDayKind.legs,
    PlanDayKind.conditioning,
  ],
};

final class PlanDay {
  const PlanDay({
    required this.date,
    this.kind,
    this.exercises = const [],
    this.replacedFrom = const {},
  });

  final DateTime date;

  /// Null on a rest day.
  final PlanDayKind? kind;
  final List<SuggestedSet> exercises;

  /// Replacement exercise id -> the exercise the plan originally had there.
  final Map<String, CatalogExercise> replacedFrom;

  bool get isRest => kind == null;

  Set<MuscleGroup> get muscleGroups => {
    for (final s in exercises) ...s.exercise.primaryMuscleGroups,
  };
}

final class WeeklyPlan {
  const WeeklyPlan({
    required this.weekStart,
    required this.weekIndex,
    required this.days,
    this.isCalibration = false,
  });

  /// The Monday this plan starts on.
  final DateTime weekStart;

  /// Weeks since [kPlanEpoch]; drives the variation.
  final int weekIndex;

  /// Exactly seven, Monday first.
  final List<PlanDay> days;

  /// Nothing was logged before this week: a lighter calibration week.
  final bool isCalibration;

  Iterable<PlanDay> get trainingDays => days.where((d) => !d.isRest);

  PlanDay? dayFor(DateTime date) {
    for (final day in days) {
      if (day.date.year == date.year &&
          day.date.month == date.month &&
          day.date.day == date.day) {
        return day;
      }
    }
    return null;
  }
}

/// A fixed Monday the week index counts from. Any Monday works; changing it
/// reshuffles every user's plan once.
final DateTime kPlanEpoch = DateTime(2026, 1, 5);

DateTime mondayOf(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

int weekIndexOf(DateTime date) {
  final monday = mondayOf(date);
  final days = DateTime.utc(monday.year, monday.month, monday.day)
      .difference(
        DateTime.utc(kPlanEpoch.year, kPlanEpoch.month, kPlanEpoch.day),
      )
      .inDays;
  return days < 0 ? 0 : days ~/ 7;
}

WeeklyPlan generateWeeklyPlan({
  required CoachEngine engine,
  required DateTime asOf,
  TrainingProfile? profile,
}) {
  final settings = profile ?? engine.profile;
  final count = settings.daysPerWeek.clamp(3, 7);
  final weekStart = mondayOf(asOf);
  final weekIndex = weekIndexOf(asOf);
  final weekdays = _trainingWeekdays[count]!;
  final split = _splits[count]!;

  final calibration = engine.isNewLifterOn(weekStart);

  final cardio = engine.available.where((e) => e.isCardio).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final indoorCardio = cardio.where((e) => !e.isOutdoor).toList();
  final outdoorCardio = cardio.where((e) => e.isOutdoor).toList();

  final days = <PlanDay>[];
  for (var weekday = 1; weekday <= 7; weekday++) {
    final date = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + weekday - 1,
    );
    final ordinal = weekdays.indexOf(weekday);
    if (ordinal < 0) {
      days.add(PlanDay(date: date));
      continue;
    }
    final kind = split[ordinal];
    final chosen = <CatalogExercise>[];
    final allSlots = _slots[kind]!;
    final slots = calibration && allSlots.length > 4
        ? allSlots.sublist(0, 4)
        : allSlots;
    for (var slot = 0; slot < slots.length; slot++) {
      final candidates = engine
          .candidatesFor(
            slots[slot],
            limit: 50,
            excludeIds: {for (final e in chosen) e.id},
            historyBefore: weekStart,
          )
          .toList();
      if (candidates.isEmpty) continue;
      // Main lifts rotate every two weeks, accessories every week.
      final rotation = slot < 2 ? weekIndex ~/ 2 : weekIndex;
      chosen.add(candidates[(rotation + ordinal) % candidates.length]);
    }

    final wantsFinisher =
        kind == PlanDayKind.conditioning ||
        settings.goal == TrainingGoal.weightLoss ||
        (settings.goal == TrainingGoal.generalFitness &&
            (kind == PlanDayKind.lower ||
                kind == PlanDayKind.legs ||
                kind == PlanDayKind.fullBodyC));
    if (wantsFinisher) {
      final preferOutdoor =
          kind == PlanDayKind.conditioning || (weekIndex + ordinal).isEven;
      final pool = preferOutdoor && outdoorCardio.isNotEmpty
          ? outdoorCardio
          : (indoorCardio.isNotEmpty ? indoorCardio : outdoorCardio);
      if (pool.isNotEmpty) {
        chosen.add(pool[(weekIndex + ordinal) % pool.length]);
      }
    }

    days.add(
      PlanDay(
        date: date,
        kind: kind,
        exercises: [
          for (final e in chosen)
            calibration
                ? _calibrationSet(engine.suggestFor(e, before: date))
                : engine.suggestFor(e, before: date),
        ],
      ),
    );
  }

  return WeeklyPlan(
    weekStart: weekStart,
    weekIndex: weekIndex,
    days: days,
    isCalibration: calibration,
  );
}

/// Two sets, not three or four, in the first week. Cardio is left alone.
SuggestedSet _calibrationSet(SuggestedSet s) =>
    s.basis == SuggestionBasis.cardio || s.sets <= 2 ? s : s.copyWith(sets: 2);

/// [plan] with each of [swaps] laid over its day: the original exercise's
/// slot now holds the replacement, prescribed from the user's own history.
/// Swaps for other weeks, or for an exercise no longer on that day, are
/// ignored.
WeeklyPlan applySwaps(
  WeeklyPlan plan,
  Iterable<PlanSwap> swaps, {
  required CoachEngine engine,
}) {
  if (swaps.isEmpty) return plan;
  return WeeklyPlan(
    weekStart: plan.weekStart,
    weekIndex: plan.weekIndex,
    isCalibration: plan.isCalibration,
    days: [for (final day in plan.days) _swapDay(day, plan, swaps, engine)],
  );
}

PlanDay _swapDay(
  PlanDay day,
  WeeklyPlan plan,
  Iterable<PlanSwap> swaps,
  CoachEngine engine,
) {
  final mine = {
    for (final swap in swaps)
      if (swap.planDate.year == day.date.year &&
          swap.planDate.month == day.date.month &&
          swap.planDate.day == day.date.day)
        swap.originalExerciseId: swap.replacementExerciseId,
  };
  if (mine.isEmpty || day.isRest) return day;
  final replacedFrom = <String, CatalogExercise>{};
  final exercises = <SuggestedSet>[];
  for (final s in day.exercises) {
    final replacementId = mine[s.exercise.id];
    final replacement = replacementId == null
        ? null
        : engine.exerciseById(replacementId);
    if (replacement == null ||
        day.exercises.any((other) => other.exercise.id == replacement.id)) {
      exercises.add(s);
      continue;
    }
    final suggestion = engine.suggestFor(replacement, before: day.date);
    exercises.add(
      plan.isCalibration ? _calibrationSet(suggestion) : suggestion,
    );
    replacedFrom[replacement.id] = s.exercise;
  }
  return PlanDay(
    date: day.date,
    kind: day.kind,
    exercises: exercises,
    replacedFrom: replacedFrom,
  );
}
