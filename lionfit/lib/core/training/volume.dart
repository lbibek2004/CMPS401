/// Volume tracking and the muscle-intensity rollup that drives the 3D map.
///
/// Two different questions, deliberately separated:
///
/// * [VolumeEngine.weeklyVolume] - **how much work**, in absolute terms: sets,
///   reps, and tonnage per muscle group for one week. This is the number a
///   lifter compares to a programme ("10-20 hard sets per muscle per week").
/// * [VolumeEngine.muscleIntensity] - **how lit up should this muscle look**,
///   0.0 to 1.0 per [MuscleGroup], over a 1-30 day window.
///
/// ## Normalized against the lifter, never against a stranger
///
/// Intensity is each group's window total divided by the **largest total that
/// same lifter has ever produced for that group over a window of the same
/// length**. Comparing a first-semester student's tonnage to a competitive
/// lifter's tells you nothing; comparing their chest week to their own best
/// chest week tells them exactly what they wanted to know. The best window a
/// lifter has ever had reads 1.0, by construction - no magic constants, no
/// clamping artifacts.
///
/// When there is not yet a full prior window to compare against, the baseline
/// falls back to the hardest-trained group **in the current window**
/// ([IntensityBaseline.currentWindow]), so a brand-new user still gets a
/// readable map instead of an all-cold body. The report says which baseline was
/// used; show it rather than implying a week-one map means the same thing as a
/// week-twenty one.
///
/// ## Default metric: hard sets, not tonnage
///
/// [IntensityMetric.hardSets] is the default. Set count is the best-supported
/// dose proxy in the hypertrophy literature, and - more practically - tonnage
/// is zero for every bodyweight exercise. A user whose back day is pull-ups
/// would see cold lats on the 3D map, which reads as a bug. Tonnage and a
/// blend of the two are available for callers that want them.
///
/// ## Warm-ups
///
/// Excluded by default ([SetType.countsAsVolume]): a warm-up is not stimulus,
/// and counting it inflates both the weekly set count and the map.
///
/// ## The four muscles with no 3D geometry
///
/// Erector spinae, obliques, rhomboids, and tibialis anterior have no mesh in
/// `assets/muscleAnatomy.glb`, and the 16-key [MuscleGroup] enum is a contract
/// with both the asset and the database, so no 17th key is invented here. They
/// live in [UnmappedRegion] instead, and their volume is handled twice over:
///
/// 1. **Attributed** to [UnmappedRegion.mapsTo] at [VolumeEngine.unmappedShare]
///    (rows -> lats, obliques -> abs, lower back -> glutes, tibialis ->
///    calves), so a deadlift lights something up rather than nothing.
/// 2. **Reported on its own** in [WeeklyVolumeReport.byUnmappedRegion], so the
///    volume is never silently lost and the UI can say where it went.
///
/// A half share, not a full one, because the fallback group is usually already
/// collecting its own primary share from the very same exercise.
library;

import 'models.dart';

/// What "intensity" is measured in.
enum IntensityMetric {
  /// Weighted count of hard sets. The default; see the library doc comment.
  hardSets,

  /// Sets x reps x weight. Zero for bodyweight work, which is why it is not
  /// the default.
  tonnage,

  /// The mean of the two normalized results.
  blended,
}

/// What the 0-1 scale was measured against.
enum IntensityBaseline {
  /// The lifter's own best window of the same length. The real thing.
  ownHistory,

  /// Not enough history for a prior window, so the hardest-trained group in the
  /// current window reads 1.0.
  currentWindow,

  /// Nothing logged in the window.
  noData,
}

/// How to treat volume for muscles the 3D model cannot draw.
enum UnmappedVolumePolicy {
  /// Add a partial share to [UnmappedRegion.mapsTo]. The default.
  attributeToFallback,

  /// Report it separately but keep it off the map entirely.
  reportOnly,
}

/// Work done by one muscle group over some period.
final class MuscleVolume {
  const MuscleVolume({this.setCount = 0, this.reps = 0, this.tonnageLb = 0});

  /// Hard sets, weighted by how much of the set this group did (primary movers
  /// count fully, assisting movers fractionally), so this is a double.
  final double setCount;

  /// Reps, weighted the same way.
  final double reps;

  /// Sets x reps x weight, weighted the same way.
  final double tonnageLb;

  static const MuscleVolume zero = MuscleVolume();

  bool get isEmpty => setCount == 0 && reps == 0 && tonnageLb == 0;

  MuscleVolume operator +(MuscleVolume other) => MuscleVolume(
    setCount: setCount + other.setCount,
    reps: reps + other.reps,
    tonnageLb: tonnageLb + other.tonnageLb,
  );

  MuscleVolume scaled(double share) => MuscleVolume(
    setCount: setCount * share,
    reps: reps * share,
    tonnageLb: tonnageLb * share,
  );

  @override
  bool operator ==(Object other) =>
      other is MuscleVolume &&
      other.setCount == setCount &&
      other.reps == reps &&
      other.tonnageLb == tonnageLb;

  @override
  int get hashCode => Object.hash(setCount, reps, tonnageLb);

  @override
  String toString() =>
      'MuscleVolume(${formatTrimmed(setCount)} sets, '
      '${formatTrimmed(reps)} reps, ${formatTrimmed(tonnageLb)} lb)';
}

/// One week of volume, per muscle group.
final class WeeklyVolumeReport {
  const WeeklyVolumeReport({
    required this.weekStart,
    required this.weekEnd,
    required this.byMuscleGroup,
    required this.byUnmappedRegion,
    required this.unknownExerciseIds,
  });

  /// First day of the week, inclusive, time stripped.
  final DateTime weekStart;

  /// Last day of the week, inclusive, time stripped.
  final DateTime weekEnd;

  /// Every one of the 16 groups, so a caller can repaint the whole model
  /// without null checks. Untrained groups are [MuscleVolume.zero].
  final Map<MuscleGroup, MuscleVolume> byMuscleGroup;

  /// Volume for the four regions the 3D model cannot draw, at full share, kept
  /// so nothing disappears. See the library doc comment.
  final Map<UnmappedRegion, MuscleVolume> byUnmappedRegion;

  /// Exercise ids in the logs that are not in the catalog - their volume could
  /// not be attributed to any muscle. Surface this rather than losing sets.
  final Set<String> unknownExerciseIds;

  MuscleVolume forGroup(MuscleGroup group) =>
      byMuscleGroup[group] ?? MuscleVolume.zero;

  double get totalTonnageLb =>
      byMuscleGroup.values.fold(0, (sum, volume) => sum + volume.tonnageLb);

  double get totalHardSets =>
      byMuscleGroup.values.fold(0, (sum, volume) => sum + volume.setCount);

  /// Groups trained at all this week, heaviest first by set count.
  List<MuscleGroup> get trainedGroups {
    final trained =
        byMuscleGroup.entries.where((entry) => !entry.value.isEmpty).toList()
          ..sort((a, b) => b.value.setCount.compareTo(a.value.setCount));
    return trained.map((entry) => entry.key).toList(growable: false);
  }
}

/// Per-muscle intensity over a rolling window, ready to drive the 3D map.
final class MuscleIntensityReport {
  const MuscleIntensityReport({
    required this.windowStart,
    required this.windowEnd,
    required this.windowDays,
    required this.metric,
    required this.baseline,
    required this.byMuscleGroup,
    required this.rawByMuscleGroup,
    required this.unknownExerciseIds,
  });

  /// First day of the window, inclusive, time stripped.
  final DateTime windowStart;

  /// Last day of the window, inclusive, time stripped - normally today.
  final DateTime windowEnd;

  final int windowDays;

  final IntensityMetric metric;

  /// What the 0-1 scale was measured against.
  final IntensityBaseline baseline;

  /// 0.0-1.0 for every one of the 16 groups - exactly the 16
  /// `baseColorFactor` writes the renderer needs.
  final Map<MuscleGroup, double> byMuscleGroup;

  /// The unnormalized metric per group, for tooltips and debugging.
  final Map<MuscleGroup, double> rawByMuscleGroup;

  final Set<String> unknownExerciseIds;

  double forGroup(MuscleGroup group) => byMuscleGroup[group] ?? 0;

  /// The groups that were trained in this window at all.
  List<MuscleGroup> get trainedGroups => byMuscleGroup.entries
      .where((entry) => entry.value > 0)
      .map((entry) => entry.key)
      .toList(growable: false);
}

/// Rolls logged sets up into weekly volume and muscle intensity.
final class VolumeEngine {
  VolumeEngine({
    required this.catalog,
    this.secondaryShare = 0.5,
    this.unmappedShare = 0.5,
    this.includeWarmUps = false,
    this.unmappedPolicy = UnmappedVolumePolicy.attributeToFallback,
  }) {
    if (secondaryShare < 0 || secondaryShare > 1) {
      throw ArgumentError.value(
        secondaryShare,
        'secondaryShare',
        'Must be between 0 and 1',
      );
    }
    if (unmappedShare < 0 || unmappedShare > 1) {
      throw ArgumentError.value(
        unmappedShare,
        'unmappedShare',
        'Must be between 0 and 1',
      );
    }
  }

  final ExerciseCatalog catalog;

  /// Share of a set credited to each assisting mover. 0.5 is the common
  /// convention for counting indirect volume.
  final double secondaryShare;

  /// Share credited to an [UnmappedRegion]'s fallback group.
  final double unmappedShare;

  /// Warm-ups are excluded by default: they are not stimulus.
  final bool includeWarmUps;

  final UnmappedVolumePolicy unmappedPolicy;

  /// Volume for the week containing [weekOf].
  ///
  /// Weeks start on [weekStartsOn] (Monday by default, matching
  /// [DateTime.monday]) and run seven days, inclusive at both ends.
  WeeklyVolumeReport weeklyVolume(
    Iterable<LoggedSet> sets, {
    required DateTime weekOf,
    int weekStartsOn = DateTime.monday,
  }) {
    if (weekStartsOn < DateTime.monday || weekStartsOn > DateTime.sunday) {
      throw ArgumentError.value(
        weekStartsOn,
        'weekStartsOn',
        'Must be a DateTime weekday constant (1-7)',
      );
    }
    final anchor = _dayOf(weekOf);
    final offset = (anchor.weekday - weekStartsOn + 7) % 7;
    final start = _addDays(anchor, -offset);
    final end = _addDays(start, 6);

    final byGroup = <MuscleGroup, MuscleVolume>{
      for (final group in MuscleGroup.values) group: MuscleVolume.zero,
    };
    final byRegion = <UnmappedRegion, MuscleVolume>{};
    final unknown = <String>{};

    for (final set in sets) {
      if (!_counts(set)) {
        continue;
      }
      final day = set.day;
      if (day.isBefore(start) || day.isAfter(end)) {
        continue;
      }
      final definition = catalog.lookup(set.exerciseId);
      if (definition == null) {
        unknown.add(set.exerciseId);
        continue;
      }
      final volume = _volumeOf(set);
      for (final group in definition.primaryMuscleGroups) {
        byGroup[group] = byGroup[group]! + volume;
      }
      for (final group in definition.secondaryMuscleGroups) {
        byGroup[group] = byGroup[group]! + volume.scaled(secondaryShare);
      }
      for (final region in definition.unmappedRegions) {
        byRegion[region] = (byRegion[region] ?? MuscleVolume.zero) + volume;
        if (unmappedPolicy == UnmappedVolumePolicy.attributeToFallback) {
          byGroup[region.mapsTo] =
              byGroup[region.mapsTo]! + volume.scaled(unmappedShare);
        }
      }
    }

    return WeeklyVolumeReport(
      weekStart: start,
      weekEnd: end,
      byMuscleGroup: Map.unmodifiable(byGroup),
      byUnmappedRegion: Map.unmodifiable(byRegion),
      unknownExerciseIds: Set.unmodifiable(unknown),
    );
  }

  /// Muscle intensity over the [windowDays] ending on [asOf], inclusive.
  ///
  /// [windowDays] must be 1-30, the range the Progress screen offers. The
  /// window is computed in **calendar days**, not 24-hour blocks, so a 30-day
  /// window ending 2 March starts 1 February and a daylight-saving shift cannot
  /// quietly drop an hour's worth of sets.
  MuscleIntensityReport muscleIntensity({
    required Iterable<LoggedSet> sets,
    required DateTime asOf,
    required int windowDays,
    IntensityMetric metric = IntensityMetric.hardSets,
  }) {
    if (windowDays < 1 || windowDays > 30) {
      throw ArgumentError.value(
        windowDays,
        'windowDays',
        'The progress window is 1-30 days',
      );
    }
    if (metric == IntensityMetric.blended) {
      return _blend(sets: sets, asOf: asOf, windowDays: windowDays);
    }

    final windowEnd = _dayOf(asOf);
    final windowStart = _addDays(windowEnd, -(windowDays - 1));

    final unknown = <String>{};
    final daily = _dailyMetric(sets, metric, unknown, upTo: windowEnd);

    final current = <MuscleGroup, double>{
      for (final group in MuscleGroup.values)
        group: _sumRange(daily[group]!, windowStart, windowEnd),
    };

    final earliest = _earliestDay(daily);
    final baselineByGroup = <MuscleGroup, double>{};
    var baselineKind = IntensityBaseline.ownHistory;

    // A prior window exists only if there is logged work before this window
    // started; otherwise every "historical" window is this one.
    final hasPriorHistory = earliest != null && earliest.isBefore(windowStart);
    if (hasPriorHistory) {
      for (final group in MuscleGroup.values) {
        baselineByGroup[group] = _bestWindowTotal(
          daily[group]!,
          from: earliest,
          to: windowEnd,
          windowDays: windowDays,
        );
      }
    } else {
      final peak = current.values.fold<double>(0, (a, b) => a > b ? a : b);
      baselineKind = peak > 0
          ? IntensityBaseline.currentWindow
          : IntensityBaseline.noData;
      for (final group in MuscleGroup.values) {
        baselineByGroup[group] = peak;
      }
    }

    final normalized = <MuscleGroup, double>{};
    for (final group in MuscleGroup.values) {
      final baselineValue = baselineByGroup[group] ?? 0;
      final value = current[group] ?? 0;
      normalized[group] = baselineValue <= 0
          ? 0
          : (value / baselineValue).clamp(0, 1).toDouble();
    }

    return MuscleIntensityReport(
      windowStart: windowStart,
      windowEnd: windowEnd,
      windowDays: windowDays,
      metric: metric,
      baseline: baselineKind,
      byMuscleGroup: Map.unmodifiable(normalized),
      rawByMuscleGroup: Map.unmodifiable(current),
      unknownExerciseIds: Set.unmodifiable(unknown),
    );
  }

  // --- internals ------------------------------------------------------------

  MuscleIntensityReport _blend({
    required Iterable<LoggedSet> sets,
    required DateTime asOf,
    required int windowDays,
  }) {
    final bySets = muscleIntensity(
      sets: sets,
      asOf: asOf,
      windowDays: windowDays,
      metric: IntensityMetric.hardSets,
    );
    final byTonnage = muscleIntensity(
      sets: sets,
      asOf: asOf,
      windowDays: windowDays,
      metric: IntensityMetric.tonnage,
    );
    final blended = <MuscleGroup, double>{
      for (final group in MuscleGroup.values)
        group: (bySets.forGroup(group) + byTonnage.forGroup(group)) / 2,
    };
    return MuscleIntensityReport(
      windowStart: bySets.windowStart,
      windowEnd: bySets.windowEnd,
      windowDays: windowDays,
      metric: IntensityMetric.blended,
      baseline: bySets.baseline,
      byMuscleGroup: Map.unmodifiable(blended),
      rawByMuscleGroup: bySets.rawByMuscleGroup,
      unknownExerciseIds: bySets.unknownExerciseIds,
    );
  }

  bool _counts(LoggedSet set) =>
      includeWarmUps ? set.reps > 0 : set.countsAsVolume && set.reps > 0;

  MuscleVolume _volumeOf(LoggedSet set) => MuscleVolume(
    setCount: 1,
    reps: set.reps.toDouble(),
    tonnageLb: set.tonnageLb,
  );

  double _metricOf(LoggedSet set, IntensityMetric metric) => switch (metric) {
    IntensityMetric.hardSets => 1,
    IntensityMetric.tonnage => set.tonnageLb,
    IntensityMetric.blended => 1,
  };

  /// Per-group, per-day totals for the whole history up to [upTo].
  Map<MuscleGroup, Map<DateTime, double>> _dailyMetric(
    Iterable<LoggedSet> sets,
    IntensityMetric metric,
    Set<String> unknown, {
    required DateTime upTo,
  }) {
    final daily = <MuscleGroup, Map<DateTime, double>>{
      for (final group in MuscleGroup.values) group: <DateTime, double>{},
    };
    for (final set in sets) {
      if (!_counts(set)) {
        continue;
      }
      final day = set.day;
      if (day.isAfter(upTo)) {
        continue;
      }
      final definition = catalog.lookup(set.exerciseId);
      if (definition == null) {
        unknown.add(set.exerciseId);
        continue;
      }
      final value = _metricOf(set, metric);
      for (final group in definition.primaryMuscleGroups) {
        _add(daily[group]!, day, value);
      }
      for (final group in definition.secondaryMuscleGroups) {
        _add(daily[group]!, day, value * secondaryShare);
      }
      if (unmappedPolicy == UnmappedVolumePolicy.attributeToFallback) {
        for (final region in definition.unmappedRegions) {
          _add(daily[region.mapsTo]!, day, value * unmappedShare);
        }
      }
    }
    return daily;
  }

  static void _add(Map<DateTime, double> into, DateTime day, double value) {
    into[day] = (into[day] ?? 0) + value;
  }

  static double _sumRange(
    Map<DateTime, double> daily,
    DateTime from,
    DateTime to,
  ) {
    var total = 0.0;
    for (final entry in daily.entries) {
      if (entry.key.isBefore(from) || entry.key.isAfter(to)) {
        continue;
      }
      total += entry.value;
    }
    return total;
  }

  /// The largest total this group has produced over any window of
  /// [windowDays] ending between [from] and [to] - the lifter's own ceiling.
  static double _bestWindowTotal(
    Map<DateTime, double> daily, {
    required DateTime from,
    required DateTime to,
    required int windowDays,
  }) {
    if (daily.isEmpty) {
      return 0;
    }
    var best = 0.0;
    var end = to;
    while (!end.isBefore(from)) {
      final start = _addDays(end, -(windowDays - 1));
      final total = _sumRange(daily, start, end);
      if (total > best) {
        best = total;
      }
      end = _addDays(end, -1);
    }
    return best;
  }

  static DateTime? _earliestDay(Map<MuscleGroup, Map<DateTime, double>> daily) {
    DateTime? earliest;
    for (final byDay in daily.values) {
      for (final day in byDay.keys) {
        if (earliest == null || day.isBefore(earliest)) {
          earliest = day;
        }
      }
    }
    return earliest;
  }

  static DateTime _dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  /// Calendar-day arithmetic. `DateTime(2026, 3, 2 - 29)` normalizes to
  /// 1 February 2026 - month lengths, leap years, and daylight saving are the
  /// constructor's problem, not ours. Adding a `Duration` would not be: it
  /// counts 24-hour blocks and shifts by an hour across a DST boundary.
  static DateTime _addDays(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);
}
