/// Per-exercise progress points for the line chart, and the week-over-week
/// summary on the home page.
///
/// Loaded lifts plot best estimated 1RM per session day - one number that
/// moves whether the lifter added weight or reps. Bodyweight and cardio plot
/// the best rep count (minutes, for cardio) instead.
///
/// Pure Dart.
library;

import '../../../core/training/one_rep_max.dart';
import '../../workout/domain/workout_models.dart';

enum ProgressMetric { e1rm, reps }

final class ProgressPoint {
  const ProgressPoint(this.day, this.value);

  final DateTime day;

  /// Pounds for [ProgressMetric.e1rm], reps (or minutes) otherwise.
  final double value;
}

final class ExerciseProgress {
  const ExerciseProgress({
    required this.exerciseId,
    required this.metric,
    required this.points,
  });

  final String exerciseId;
  final ProgressMetric metric;

  /// One per day, oldest first.
  final List<ProgressPoint> points;

  /// First point to last, as a fraction; null with fewer than two points.
  double? get change {
    if (points.length < 2 || points.first.value == 0) return null;
    return (points.last.value - points.first.value) / points.first.value;
  }
}

ExerciseProgress exerciseProgress(String exerciseId, Iterable<SetRecord> sets) {
  final mine = [
    for (final s in sets)
      if (s.exerciseId == exerciseId && s.setType.countsAsVolume) s,
  ];
  final loaded = mine.any((s) => (s.weight ?? 0) > 0);
  final byDay = <DateTime, double>{};
  for (final set in mine) {
    final double? value = loaded
        ? e1rmForSet(set.toLoggedSet())
        : set.reps?.toDouble();
    if (value == null) continue;
    final best = byDay[set.performedOn];
    if (best == null || value > best) byDay[set.performedOn] = value;
  }
  final days = byDay.keys.toList()..sort();
  return ExerciseProgress(
    exerciseId: exerciseId,
    metric: loaded ? ProgressMetric.e1rm : ProgressMetric.reps,
    points: [for (final day in days) ProgressPoint(day, byDay[day]!)],
  );
}

/// Exercise ids ordered by how often they were logged, most first - the
/// sensible default order for the chart's picker.
List<String> exercisesByFrequency(Iterable<SetRecord> sets) {
  final days = <String, Set<DateTime>>{};
  for (final set in sets) {
    if (!set.setType.countsAsVolume) continue;
    days.putIfAbsent(set.exerciseId, () => {}).add(set.performedOn);
  }
  final ids = days.keys.toList()
    ..sort((a, b) => days[b]!.length.compareTo(days[a]!.length));
  return ids;
}

/// This week against last week, Monday-based.
final class WeekComparison {
  const WeekComparison({
    required this.thisWeekSets,
    required this.lastWeekSets,
    required this.thisWeekVolumeLb,
    required this.lastWeekVolumeLb,
    required this.thisWeekDays,
  });

  final int thisWeekSets;
  final int lastWeekSets;
  final double thisWeekVolumeLb;
  final double lastWeekVolumeLb;

  /// Distinct days trained this week.
  final int thisWeekDays;
}

WeekComparison compareWeeks(
  Iterable<SetRecord> sets, {
  required DateTime asOf,
}) {
  final today = DateTime(asOf.year, asOf.month, asOf.day);
  final thisMonday = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - 1),
  );
  final lastMonday = DateTime(
    thisMonday.year,
    thisMonday.month,
    thisMonday.day - 7,
  );
  var thisSets = 0;
  var lastSets = 0;
  var thisVolume = 0.0;
  var lastVolume = 0.0;
  final days = <DateTime>{};
  for (final set in sets) {
    if (!set.setType.countsAsVolume) continue;
    final volume = set.weight == null || set.reps == null
        ? 0.0
        : set.unit.toLb(set.weight!) * set.reps!;
    if (!set.performedOn.isBefore(thisMonday) &&
        !set.performedOn.isAfter(today)) {
      thisSets++;
      thisVolume += volume;
      days.add(set.performedOn);
    } else if (!set.performedOn.isBefore(lastMonday) &&
        set.performedOn.isBefore(thisMonday)) {
      lastSets++;
      lastVolume += volume;
    }
  }
  return WeekComparison(
    thisWeekSets: thisSets,
    lastWeekSets: lastSets,
    thisWeekVolumeLb: thisVolume,
    lastWeekVolumeLb: lastVolume,
    thisWeekDays: days.length,
  );
}

/// What the progress chart compares the daily average against.
enum ProgressComparison {
  lastWeek('vs last week'),
  personalBest('vs personal best');

  const ProgressComparison(this.label);

  final String label;
}

/// One session day of one exercise: the mean over its working sets
/// (warm-ups excluded).
final class DailyAverage {
  const DailyAverage({
    required this.day,
    required this.value,
    required this.averageReps,
    required this.sets,
  });

  final DateTime day;

  /// Mean weight in pounds for loaded lifts; mean reps (minutes, for cardio)
  /// otherwise.
  final double value;
  final double averageReps;
  final int sets;
}

/// The progress chart's data for one exercise.
final class AverageProgress {
  const AverageProgress({
    required this.exerciseId,
    required this.metric,
    required this.points,
    required this.previousWeek,
    required this.runningBest,
  });

  final String exerciseId;

  /// [ProgressMetric.e1rm] here means "loaded": values are pounds.
  final ProgressMetric metric;

  /// One per session day, oldest first.
  final List<DailyAverage> points;

  /// Per point: the average over every working set of the calendar week
  /// (Mon-Sun) before that point's week, or null when that week had none.
  final List<double?> previousWeek;

  /// Per point: the best daily average up to and including it.
  final List<double> runningBest;

  bool get isLoaded => metric == ProgressMetric.e1rm;

  DailyAverage? get latest => points.isEmpty ? null : points.last;

  /// The best daily average, latest first on a tie.
  DailyAverage? get best {
    DailyAverage? top;
    for (final p in points) {
      if (top == null || p.value >= top.value) top = p;
    }
    return top;
  }

  /// The latest day against [comparison], as a fraction (0.05 = +5%).
  /// Null when there is nothing to compare with.
  double? changeVs(ProgressComparison comparison) {
    final last = latest;
    if (last == null) return null;
    final base = switch (comparison) {
      ProgressComparison.lastWeek => previousWeek.last,
      ProgressComparison.personalBest => best?.value,
    };
    if (base == null || base == 0) return null;
    return (last.value - base) / base;
  }
}

DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Daily averages of [exerciseId]'s working sets, with the previous-week and
/// personal-best comparisons the chart draws.
///
/// Loaded lifts (any set with weight) average the weight; bodyweight and
/// cardio average reps. Sets without reps, and loaded-lift sets without a
/// weight, are skipped rather than counted as zero.
AverageProgress averageProgress(String exerciseId, Iterable<SetRecord> sets) {
  final mine = [
    for (final s in sets)
      if (s.exerciseId == exerciseId &&
          s.setType.countsAsVolume &&
          (s.reps ?? 0) > 0)
        s,
  ];
  final loaded = mine.any((s) => (s.weight ?? 0) > 0);
  final used = [
    for (final s in mine)
      if (!loaded || (s.weight ?? 0) > 0) s,
  ];
  double valueOf(SetRecord s) =>
      loaded ? s.unit.toLb(s.weight!) : s.reps!.toDouble();

  final byDay = <DateTime, List<SetRecord>>{};
  for (final s in used) {
    byDay.putIfAbsent(s.performedOn, () => []).add(s);
  }
  final days = byDay.keys.toList()..sort();
  final points = [
    for (final day in days)
      DailyAverage(
        day: day,
        value:
            byDay[day]!.map(valueOf).reduce((a, b) => a + b) /
            byDay[day]!.length,
        averageReps:
            byDay[day]!.map((s) => s.reps!).reduce((a, b) => a + b) /
            byDay[day]!.length,
        sets: byDay[day]!.length,
      ),
  ];

  double? weekAverage(DateTime monday) {
    final end = DateTime(monday.year, monday.month, monday.day + 7);
    final inWeek = [
      for (final s in used)
        if (!s.performedOn.isBefore(monday) && s.performedOn.isBefore(end)) s,
    ];
    if (inWeek.isEmpty) return null;
    return inWeek.map(valueOf).reduce((a, b) => a + b) / inWeek.length;
  }

  final previousWeek = [
    for (final p in points)
      weekAverage(
        DateTime(
          _mondayOf(p.day).year,
          _mondayOf(p.day).month,
          _mondayOf(p.day).day - 7,
        ),
      ),
  ];
  final runningBest = <double>[];
  for (final p in points) {
    runningBest.add(
      runningBest.isEmpty || p.value > runningBest.last
          ? p.value
          : runningBest.last,
    );
  }
  return AverageProgress(
    exerciseId: exerciseId,
    metric: loaded ? ProgressMetric.e1rm : ProgressMetric.reps,
    points: points,
    previousWeek: previousWeek,
    runningBest: runningBest,
  );
}
