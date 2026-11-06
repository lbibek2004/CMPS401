/// The onboarding survey's "what can you lift now?" step: which exercises to
/// offer for each kind of lift. Pure Dart.
library;

import '../../workout/domain/workout_models.dart';

/// One question: a kind of lift, and the catalog exercises that answer it.
final class SurveyLiftCategory {
  const SurveyLiftCategory({
    required this.title,
    required this.example,
    required this.patterns,
    required this.preferredSlugs,
  });

  final String title;
  final String example;
  final Set<String> patterns;

  /// Offered first, in this order, when the catalog has them.
  final List<String> preferredSlugs;
}

/// One question per half of the body and direction - enough for the
/// estimator to carry a number to every other lift (`starting_load.dart`).
const kSurveyLiftCategories = [
  SurveyLiftCategory(
    title: 'A press',
    example: 'bench press, chest press, shoulder press',
    patterns: {'horizontal_push', 'vertical_push'},
    preferredSlugs: [
      'barbell_bench_press',
      'dumbbell_bench_press',
      'machine_chest_press',
      'smith_machine_bench_press',
      'dumbbell_overhead_press',
    ],
  ),
  SurveyLiftCategory(
    title: 'A squat or leg press',
    example: 'back squat, goblet squat, leg press',
    patterns: {'squat', 'lunge'},
    preferredSlugs: [
      'barbell_back_squat',
      'goblet_squat',
      'leg_press',
      'machine_leg_press',
      'smith_machine_squat',
    ],
  ),
  SurveyLiftCategory(
    title: 'A hinge',
    example: 'deadlift, Romanian deadlift, hip thrust',
    patterns: {'hinge'},
    preferredSlugs: [
      'barbell_deadlift',
      'barbell_romanian_deadlift',
      'dumbbell_romanian_deadlift',
      'barbell_hip_thrust',
    ],
  ),
  SurveyLiftCategory(
    title: 'A pull',
    example: 'lat pulldown, cable row, machine row',
    patterns: {'vertical_pull', 'horizontal_pull'},
    preferredSlugs: [
      'lat_pulldown_wide_grip',
      'seated_cable_row',
      'machine_back_row',
      'one_arm_dumbbell_row',
    ],
  ),
];

/// Active, loaded (not bodyweight, not cardio) exercises for [category]:
/// the preferred ones first in their listed order, then the rest by name.
List<CatalogExercise> surveyOptions(
  Iterable<CatalogExercise> catalog,
  SurveyLiftCategory category,
) {
  final options = [
    for (final e in catalog)
      if (e.isActive &&
          !e.isCardio &&
          !e.isBodyweightOnly &&
          category.patterns.contains(e.movementPattern))
        e,
  ];
  int rank(CatalogExercise e) {
    final i = category.preferredSlugs.indexOf(e.slug);
    return i < 0 ? category.preferredSlugs.length : i;
  }

  options.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.name.compareTo(b.name);
  });
  return options;
}
