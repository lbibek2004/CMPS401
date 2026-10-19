/// The muscle map's red / yellow / green verdict for each muscle group.
///
/// Three states, chosen for a glance at the 3D model:
///
/// | Status | Colour | Meaning |
/// | --- | --- | --- |
/// | [MuscleTrainingStatus.untrained] | red | zero hard sets in the window |
/// | [MuscleTrainingStatus.lessTrained] | yellow | some work, below target |
/// | [MuscleTrainingStatus.wellTrained] | green | at or above target |
///
/// ## The target
///
/// [kWeeklyHardSetTarget] hard sets per muscle per week - the low end of the
/// common 10-20 sets/week hypertrophy range - scaled linearly to the window
/// length, with a floor of [kMinimumHardSetTarget] so a one-day window does
/// not call a single set "well trained".
///
/// | Window | Target |
/// | --- | --- |
/// | 1 day | 3 sets (floor) |
/// | 7 days | 10 sets |
/// | 14 days | 20 sets |
/// | 30 days | ~42.9 sets |
///
/// Sets are counted the way [VolumeEngine] counts them: warm-ups excluded,
/// secondary movers at half a set, and the four muscles the model has no
/// geometry for attributed to their fallback group at half a set. So three
/// sets of bench press is 3 sets for `chest_lower` and 1.5 for `triceps`.
///
/// Pure Dart - no Flutter, no Supabase.
library;

import 'models.dart';
import 'volume.dart';

/// Hard sets per muscle group per week that count as "well trained".
const double kWeeklyHardSetTarget = 10;

/// The smallest target any window can have.
const double kMinimumHardSetTarget = 3;

/// Shortest and longest window the muscle map offers, in days.
const int kMinMapWindowDays = 1;
const int kMaxMapWindowDays = 30;

enum MuscleTrainingStatus {
  untrained('Untrained'),
  lessTrained('Less trained'),
  wellTrained('Well trained');

  const MuscleTrainingStatus(this.label);

  /// What the legend and the per-muscle list say out loud.
  final String label;
}

/// The hard-set target for a window of [windowDays] days.
double hardSetTargetFor(int windowDays) {
  _checkWindow(windowDays);
  final scaled = kWeeklyHardSetTarget * windowDays / 7;
  return scaled < kMinimumHardSetTarget ? kMinimumHardSetTarget : scaled;
}

/// The verdict for one group given its weighted hard-set count.
MuscleTrainingStatus classifyHardSets(double hardSets, double target) {
  if (hardSets <= 0) return MuscleTrainingStatus.untrained;
  if (hardSets < target) return MuscleTrainingStatus.lessTrained;
  return MuscleTrainingStatus.wellTrained;
}

/// Default window: the longest window that has data, per `CLAUDE.md`.
///
/// That is "from the first logged set up to today", clamped to 1-30. A
/// brand-new user who logged for the first time today gets a 1-day window, so
/// their first session reads against a 1-day target instead of being swamped
/// by a 30-day one. With no data at all it is 7 - an honest all-red week.
int defaultMapWindowDays(Iterable<LoggedSet> sets, {required DateTime asOf}) {
  DateTime? earliest;
  for (final set in sets) {
    if (!set.countsAsVolume) continue;
    final day = set.day;
    if (earliest == null || day.isBefore(earliest)) earliest = day;
  }
  if (earliest == null) return 7;
  final today = DateTime(asOf.year, asOf.month, asOf.day);
  // Calendar-day difference via UTC, so a daylight-saving shift cannot make
  // a 7-day span read as 6.
  final span =
      DateTime.utc(today.year, today.month, today.day)
          .difference(DateTime.utc(earliest.year, earliest.month, earliest.day))
          .inDays +
      1;
  return span.clamp(kMinMapWindowDays, kMaxMapWindowDays);
}

/// One group's line in the report.
final class MuscleStatusEntry {
  const MuscleStatusEntry({
    required this.group,
    required this.hardSets,
    required this.target,
    required this.status,
  });

  final MuscleGroup group;

  /// Weighted hard sets in the window (secondary movers count half).
  final double hardSets;

  final double target;

  final MuscleTrainingStatus status;
}

/// Every one of the 16 groups, classified, for one window.
final class MuscleStatusReport {
  const MuscleStatusReport({
    required this.windowDays,
    required this.target,
    required this.byMuscleGroup,
    required this.unknownExerciseIds,
  });

  final int windowDays;
  final double target;

  /// Always holds all 16 groups - exactly the 16 material writes the renderer
  /// needs.
  final Map<MuscleGroup, MuscleStatusEntry> byMuscleGroup;

  /// Logged exercise ids the catalog did not know. Their sets could not be
  /// attributed to any muscle; surface this rather than lose them silently.
  final Set<String> unknownExerciseIds;

  MuscleTrainingStatus statusOf(MuscleGroup group) =>
      byMuscleGroup[group]!.status;

  int countWith(MuscleTrainingStatus status) =>
      byMuscleGroup.values.where((entry) => entry.status == status).length;

  bool get hasAnyTraining =>
      byMuscleGroup.values.any((entry) => entry.hardSets > 0);
}

/// Classifies all 16 groups over the [windowDays] ending on [asOf].
MuscleStatusReport muscleStatusReport({
  required Iterable<LoggedSet> sets,
  required ExerciseCatalog catalog,
  required DateTime asOf,
  required int windowDays,
}) {
  _checkWindow(windowDays);
  final intensity = VolumeEngine(catalog: catalog)
      .muscleIntensity(sets: sets, asOf: asOf, windowDays: windowDays);
  final target = hardSetTargetFor(windowDays);
  return MuscleStatusReport(
    windowDays: windowDays,
    target: target,
    byMuscleGroup: Map.unmodifiable({
      for (final group in MuscleGroup.values)
        group: MuscleStatusEntry(
          group: group,
          hardSets: intensity.rawByMuscleGroup[group] ?? 0,
          target: target,
          status: classifyHardSets(
            intensity.rawByMuscleGroup[group] ?? 0,
            target,
          ),
        ),
    }),
    unknownExerciseIds: intensity.unknownExerciseIds,
  );
}

void _checkWindow(int windowDays) {
  if (windowDays < kMinMapWindowDays || windowDays > kMaxMapWindowDays) {
    throw ArgumentError.value(
      windowDays,
      'windowDays',
      'The muscle map window is $kMinMapWindowDays-$kMaxMapWindowDays days',
    );
  }
}
