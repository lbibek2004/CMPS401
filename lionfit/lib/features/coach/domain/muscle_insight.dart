/// What one muscle actually got from the window: which exercises touched it,
/// whether that was the point of the exercise or a side effect, and how the
/// numbers moved.
///
/// Three roles, matching how the muscle map counts sets:
///
/// | Role | Meaning | Counts on the map as |
/// | --- | --- | --- |
/// | [MuscleRole.direct] | a primary mover | 1 set |
/// | [MuscleRole.assisted] | a secondary mover (triceps on bench press) | 0.5 set |
/// | [MuscleRole.viaUnmapped] | the true target has no 3D geometry and is drawn here (rows -> lats via rhomboids) | 0.5 set |
///
/// Pure Dart.
library;

import '../../../core/training/models.dart';
import '../../../core/training/one_rep_max.dart';
import '../../workout/domain/workout_models.dart';

enum MuscleRole { direct, assisted, viaUnmapped }

/// One exercise's contribution to one muscle.
final class ExerciseContribution {
  const ExerciseContribution({
    required this.exercise,
    required this.role,
    required this.sessions,
    required this.workingSets,
    required this.totalReps,
    this.bestSet,
    this.bestE1rmLb,
    this.firstE1rmLb,
    this.lastE1rmLb,
    this.unmappedRegion,
  });

  final CatalogExercise exercise;
  final MuscleRole role;

  /// Distinct days it was done in the window.
  final int sessions;

  /// Warm-ups excluded, same as the map.
  final int workingSets;
  final int totalReps;

  /// Heaviest-by-e1RM working set, or the most reps for bodyweight work.
  final SetRecord? bestSet;
  final double? bestE1rmLb;

  /// Best e1RM on the first and the last day in the window - the trend.
  final double? firstE1rmLb;
  final double? lastE1rmLb;

  /// Set when [role] is [MuscleRole.viaUnmapped].
  final UnmappedRegion? unmappedRegion;

  /// Fractional e1RM change first day -> last day, or null with one day.
  double? get trend {
    final first = firstE1rmLb;
    final last = lastE1rmLb;
    if (first == null || last == null || sessions < 2 || first == 0) {
      return null;
    }
    return (last - first) / first;
  }
}

final class MuscleInsight {
  const MuscleInsight({
    required this.group,
    required this.contributions,
    required this.windowDays,
  });

  final MuscleGroup group;
  final int windowDays;

  /// Direct work first, then by sets.
  final List<ExerciseContribution> contributions;

  int get directSets => contributions
      .where((c) => c.role == MuscleRole.direct)
      .fold(0, (sum, c) => sum + c.workingSets);

  int get indirectSets => contributions
      .where((c) => c.role != MuscleRole.direct)
      .fold(0, (sum, c) => sum + c.workingSets);

  bool get isEmpty => contributions.isEmpty;

  /// One plain sentence for the top of the sheet.
  String get headline {
    if (isEmpty) return 'No sets touched this muscle in the window.';
    if (directSets == 0) {
      return 'Only indirect work: $indirectSets '
          '${indirectSets == 1 ? 'set' : 'sets'} where it assisted another '
          'muscle. No exercise targeted it directly.';
    }
    final indirect = indirectSets == 0
        ? ''
        : ', plus $indirectSets assisting in other lifts';
    return '$directSets direct ${directSets == 1 ? 'set' : 'sets'}$indirect.';
  }
}

/// Builds the insight for [group] from [sets] already limited to the window.
MuscleInsight muscleInsight({
  required MuscleGroup group,
  required Iterable<SetRecord> sets,
  required Map<String, CatalogExercise> exercisesById,
  required int windowDays,
}) {
  final byExercise = <String, List<SetRecord>>{};
  for (final set in sets) {
    if (!set.setType.countsAsVolume) continue;
    byExercise.putIfAbsent(set.exerciseId, () => []).add(set);
  }

  final contributions = <ExerciseContribution>[];
  for (final MapEntry(key: id, value: logged) in byExercise.entries) {
    final exercise = exercisesById[id];
    if (exercise == null) continue;

    final UnmappedRegion? region = exercise.unmappedRegions
        .where((r) => r.mapsTo == group)
        .firstOrNull;
    final MuscleRole role;
    if (exercise.primaryMuscleGroups.contains(group)) {
      role = MuscleRole.direct;
    } else if (exercise.secondaryMuscleGroups.contains(group)) {
      role = MuscleRole.assisted;
    } else if (region != null) {
      role = MuscleRole.viaUnmapped;
    } else {
      continue;
    }

    final days = <DateTime>{for (final s in logged) s.performedOn};
    final firstDay = days.reduce((a, b) => a.isBefore(b) ? a : b);
    final lastDay = days.reduce((a, b) => a.isAfter(b) ? a : b);

    SetRecord? best;
    double? bestE1rm;
    double? firstBest;
    double? lastBest;
    for (final set in logged) {
      final e1rm = e1rmForSet(set.toLoggedSet());
      if (e1rm != null) {
        if (bestE1rm == null || e1rm > bestE1rm) {
          bestE1rm = e1rm;
          best = set;
        }
        if (set.performedOn == firstDay) {
          firstBest = firstBest == null || e1rm > firstBest ? e1rm : firstBest;
        }
        if (set.performedOn == lastDay) {
          lastBest = lastBest == null || e1rm > lastBest ? e1rm : lastBest;
        }
      } else if (bestE1rm == null &&
          (best == null || (set.reps ?? 0) > (best.reps ?? 0))) {
        // Bodyweight: no e1RM, so "best" is the most reps.
        best = set;
      }
    }

    contributions.add(
      ExerciseContribution(
        exercise: exercise,
        role: role,
        sessions: days.length,
        workingSets: logged.length,
        totalReps: logged.fold(0, (sum, s) => sum + (s.reps ?? 0)),
        bestSet: best,
        bestE1rmLb: bestE1rm,
        firstE1rmLb: firstBest,
        lastE1rmLb: lastBest,
        unmappedRegion: role == MuscleRole.viaUnmapped ? region : null,
      ),
    );
  }

  contributions.sort((a, b) {
    final byRole = a.role.index.compareTo(b.role.index);
    return byRole != 0 ? byRole : b.workingSets.compareTo(a.workingSets);
  });

  return MuscleInsight(
    group: group,
    contributions: List.unmodifiable(contributions),
    windowDays: windowDays,
  );
}
