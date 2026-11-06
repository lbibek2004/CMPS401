/// First-session loads for exercises the user has never logged, from the
/// onboarding survey instead of a guess.
///
/// ## Where the number comes from, best source first
///
/// 1. **A survey answer for this exact exercise** ("bench 135 x 8"): its
///    estimated 1RM.
/// 2. **A survey answer for a related lift**, carried across with strength
///    ratios: an incline dumbbell press is estimated from the barbell bench,
///    a leg extension from the squat. Same movement pattern first, then same
///    half of the body, then any answer.
/// 3. **Bodyweight and experience**: conservative strength standards
///    (multiples of bodyweight) scaled down hard for newer lifters.
/// 4. Nothing usable (a brand-new lifter who skipped bodyweight): null, and
///    the caller starts at the lightest setting the equipment has.
///
/// Every estimate is then turned into a working load for the *top* of the
/// rep range with at least 3 reps in reserve - deliberately easy, because the
/// first session is a calibration: the user logs how hard it felt, and the
/// next load comes from that real set (see `CoachEngine.suggestFor`).
///
/// The ratios are rough population figures, not science. They only need to
/// land in the right neighbourhood; the first logged set corrects them.
///
/// Pure Dart.
library;

import '../../../core/training/models.dart';
import '../../../core/training/one_rep_max.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/domain/workout_models.dart';

/// Estimated 1RM as a multiple of bodyweight for a consistent
/// (intermediate) lifter, on the barbell version of each pattern.
const Map<String, double> kPatternStandards = {
  'squat': 1.25,
  'hinge': 1.5,
  'lunge': 0.6,
  'horizontal_push': 1.0,
  'vertical_push': 0.6,
  'horizontal_pull': 0.8,
  'vertical_pull': 0.8,
  'carry': 0.5,
  'isolation': 0.35,
  'core': 0.3,
};

/// How much of a barbell load the same pattern moves on other equipment.
/// Dumbbells are per hand.
double equipmentScale(CatalogExercise exercise) {
  final gear = exercise.requiredEquipment.toSet();
  bool any(Iterable<String> slugs) => slugs.any(gear.contains);
  if (any(const ['dumbbell_pair', 'seated_shoulder_press_bench'])) return 0.4;
  if (any(const ['kettlebells'])) return 0.35;
  if (any(const ['medicine_balls'])) return 0.15;
  if (any(const [
    'adjustable_cable_station',
    'functional_trainer',
    'high_pulley',
    'cable_row',
    'lat_pulldown',
  ])) {
    return 0.65;
  }
  if (any(const ['smith_machine'])) return 0.9;
  if (any(const [
    'bench_press',
    'fixed_barbell',
    'deadlift_platform',
    'ez_curl_bar',
  ])) {
    return 1.0;
  }
  // Selectorized and plate-loaded machines. Stacks vary by brand; 0.85 errs
  // light.
  return 0.85;
}

/// Experience scaling on top of [kPatternStandards].
double experienceFactor(TrainingExperience? experience) => switch (experience) {
  TrainingExperience.brandNew => 0.35,
  TrainingExperience.beginner || null => 0.55,
  TrainingExperience.intermediate => 0.8,
  TrainingExperience.advanced => 1.0,
};

/// Assumed when the survey skipped bodyweight. Only used for lifters past
/// "brand new" - a first-timer starts at the lightest setting instead.
const double kDefaultBodyweightLb = 150;

const _lowerBody = {
  MuscleGroup.quads,
  MuscleGroup.hamstrings,
  MuscleGroup.glutes,
  MuscleGroup.calves,
  MuscleGroup.adductors,
};

bool isLowerBody(CatalogExercise exercise) =>
    exercise.primaryMuscleGroups.isNotEmpty &&
    _lowerBody.contains(exercise.primaryMuscleGroups.first);

/// An estimated 1RM and a sentence saying where it came from.
typedef StartingEstimate = ({double e1rmLb, String source});

final class StartingLoadEstimator {
  StartingLoadEstimator({
    required Iterable<StrengthBaseline> baselines,
    required Map<String, CatalogExercise> catalog,
    this.experience,
    this.bodyweightLb,
  }) : _anchors = [
         for (final b in baselines)
           if (catalog[b.exerciseId] case final exercise?)
             if (_e1rm(b) case final e1rm?)
               (exercise: exercise, baseline: b, e1rmLb: e1rm),
       ];

  final TrainingExperience? experience;
  final double? bodyweightLb;
  final List<
    ({CatalogExercise exercise, StrengthBaseline baseline, double e1rmLb})
  >
  _anchors;

  bool get hasBaselines => _anchors.isNotEmpty;

  static double? _e1rm(StrengthBaseline b) {
    if (b.weightLb <= 0 || b.reps < 1) return null;
    return estimateE1rm(loadLb: b.weightLb, reps: b.reps.clamp(1, 30));
  }

  static double _relativeStrength(CatalogExercise e) =>
      (kPatternStandards[e.movementPattern] ?? 0.35) * equipmentScale(e);

  /// Null for cardio and bodyweight work, and when there is nothing to go on.
  StartingEstimate? estimate(CatalogExercise exercise) {
    if (exercise.isCardio || exercise.isBodyweightOnly) return null;

    // 1. This exact exercise.
    for (final a in _anchors) {
      if (a.exercise.id == exercise.id) {
        return (
          e1rmLb: a.e1rmLb,
          source:
              'From your survey: ${formatTrimmed(a.baseline.weight)} '
              '${a.baseline.unit.wireName} × ${a.baseline.reps}.',
        );
      }
    }

    // 2. A related survey lift, carried across by relative strength.
    final anchor =
        _firstWhereOrNull(
          (a) => a.exercise.movementPattern == exercise.movementPattern,
        ) ??
        _firstWhereOrNull(
          (a) => isLowerBody(a.exercise) == isLowerBody(exercise),
        ) ??
        (_anchors.isEmpty ? null : _anchors.first);
    if (anchor != null) {
      final ratio =
          _relativeStrength(exercise) / _relativeStrength(anchor.exercise);
      return (
        e1rmLb: anchor.e1rmLb * ratio,
        source: 'Estimated from your ${anchor.exercise.name} in the survey.',
      );
    }

    // 3. Bodyweight and experience.
    if (bodyweightLb == null && experience == TrainingExperience.brandNew) {
      return null;
    }
    final bodyweight = bodyweightLb ?? kDefaultBodyweightLb;
    return (
      e1rmLb:
          bodyweight *
          _relativeStrength(exercise) *
          experienceFactor(experience),
      source: bodyweightLb == null
          ? 'Estimated from your experience level.'
          : 'Estimated from your bodyweight and experience.',
    );
  }

  /// The easy first working load for [targetReps], in pounds, before
  /// rounding to the equipment. At least 3 reps in reserve at the top of the
  /// rep range.
  double? firstWorkingLoadLb(
    CatalogExercise exercise, {
    required RepRange targetReps,
    double targetRir = 2,
  }) {
    final estimate = this.estimate(exercise);
    if (estimate == null) return null;
    return loadForReps(
      e1rmLb: estimate.e1rmLb,
      reps: targetReps.max,
      repsInReserve: targetRir < 3 ? 3 : targetRir,
    );
  }

  ({CatalogExercise exercise, StrengthBaseline baseline, double e1rmLb})?
  _firstWhereOrNull(
    bool Function(
      ({CatalogExercise exercise, StrengthBaseline baseline, double e1rmLb}),
    )
    test,
  ) {
    for (final a in _anchors) {
      if (test(a)) return a;
    }
    return null;
  }
}
