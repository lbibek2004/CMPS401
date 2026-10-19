/// Core value types for LionFit's training engine.
///
/// **Pure Dart on purpose.** Nothing under `lib/core/training/` imports Flutter,
/// Riverpod, or Supabase, so every number the app shows a user is unit-testable
/// without a widget tree.
///
/// **Canonical unit: pounds.** Every engine in this directory computes in lb
/// (the Pennington rack and the plate denominations are imperial). [WeightUnit]
/// converts at the boundary - UI in, display out - which is the
/// single-canonical-unit rule from `CLAUDE.md` -> Conventions.
///
/// Nothing here diagnoses, prescribes for an injury, or interprets a heart rate.
/// This is training arithmetic, not medical advice.
library;

/// The 16 colorable muscle groups.
///
/// [wireName] is the canonical key in three places that must stay in lockstep:
/// the `muscle_group` Postgres enum, `exercises.primary_muscle_groups`, and the
/// **material names inside `assets/muscleAnatomy.glb`**. A typo here does not
/// throw - it silently paints nothing on the 3D map - so these strings are
/// written out verbatim rather than derived from the Dart identifier.
///
/// Verify against the asset with `node tool/inspect_glb.js assets/muscleAnatomy.glb`.
enum MuscleGroup {
  abs('abs'),
  adductors('adductors'),
  biceps('biceps'),
  calves('calves'),
  chestLower('chest_lower'),
  chestUpper('chest_upper'),
  deltsFront('delts_front'),
  deltsRear('delts_rear'),
  deltsSide('delts_side'),
  forearms('forearms'),
  glutes('glutes'),
  hamstrings('hamstrings'),
  lats('lats'),
  quads('quads'),
  trapsUpper('traps_upper'),
  triceps('triceps');

  const MuscleGroup(this.wireName);

  /// The database enum value and the GLB material name. Never derive this from
  /// [name] - `chestLower` and `chest_lower` are not the same string.
  final String wireName;

  /// Parses a wire name, throwing on anything that is not one of the 16 keys.
  static MuscleGroup fromWireName(String wireName) => values.firstWhere(
    (group) => group.wireName == wireName,
    orElse: () => throw ArgumentError.value(
      wireName,
      'wireName',
      'Not one of the 16 LionFit muscle group keys',
    ),
  );

  /// Parses a wire name, returning `null` instead of throwing.
  static MuscleGroup? tryFromWireName(String wireName) {
    for (final group in values) {
      if (group.wireName == wireName) {
        return group;
      }
    }
    return null;
  }
}

/// Muscles a lifting app needs that **have no geometry in `muscleAnatomy.glb`**.
///
/// These are deliberately *not* [MuscleGroup] values: that enum is a fixed
/// 16-key contract shared with the database and the 3D asset, and a 17th key
/// would break the map's "16 baseColorFactor writes" repaint.
///
/// Their volume is not dropped either - a deadlift that lights up nothing reads
/// as a bug to the user. Each region carries a documented [mapsTo] fallback, and
/// the volume engine reports each region's own totals separately so the UI can
/// say "your lower-back work is shown on glutes":
///
/// | Region | Shown on | Why |
/// | --- | --- | --- |
/// | erector spinae | `glutes` | deadlifts and back extensions already train the posterior chain the model does have |
/// | obliques | `abs` | same trunk block visually |
/// | rhomboids | `lats` | every row's pulling volume is already attributed to lats |
/// | tibialis anterior | `calves` | same lower leg |
///
/// This is the fallback proposed in `CHECKLIST.md`; it is owned jointly with
/// `supabase-architect`. If Blender gains the geometry these become real
/// [MuscleGroup] values and this enum goes away.
enum UnmappedRegion {
  erectorSpinae('erector_spinae', MuscleGroup.glutes),
  obliques('obliques', MuscleGroup.abs),
  rhomboids('rhomboids', MuscleGroup.lats),
  tibialisAnterior('tibialis_anterior', MuscleGroup.calves);

  const UnmappedRegion(this.wireName, this.mapsTo);

  /// Stable key for `exercises` rows; never a `muscle_group` enum value.
  final String wireName;

  /// The 3D-mapped group this region's volume is attributed to.
  final MuscleGroup mapsTo;
}

/// How a logged set was performed.
///
/// The two flags matter to different engines:
/// * [countsAsVolume] - warm-ups are not stimulus and must not inflate the
///   muscle map or the weekly set count.
/// * [drivesLoadProgression] - only straight working sets describe the load the
///   lifter can actually handle. A drop set's weight is *deliberately* reduced,
///   so reading it as "the load you handled" would ratchet recommendations down
///   every time the user logged one.
enum SetType {
  warmUp('warm_up', countsAsVolume: false, drivesLoadProgression: false),
  working('working', countsAsVolume: true, drivesLoadProgression: true),
  dropSet('drop_set', countsAsVolume: true, drivesLoadProgression: false),
  superSet('super_set', countsAsVolume: true, drivesLoadProgression: false);

  const SetType(
    this.wireName, {
    required this.countsAsVolume,
    required this.drivesLoadProgression,
  });

  final String wireName;
  final bool countsAsVolume;
  final bool drivesLoadProgression;
}

/// Exact pounds per kilogram (international avoirdupois pound).
const double kPoundsPerKilogram = 2.2046226218487757;

/// The one unit everything in this directory computes and stores in.
const WeightUnit canonicalWeightUnit = WeightUnit.lb;

/// A unit the user may log and read weights in.
///
/// Storage and all math stay in [canonicalWeightUnit]; this converts at the
/// boundary only.
enum WeightUnit {
  lb('lb'),
  kg('kg');

  const WeightUnit(this.wireName);

  final String wireName;

  /// Converts [value], expressed in this unit, to pounds.
  double toLb(double value) =>
      this == WeightUnit.lb ? value : value * kPoundsPerKilogram;

  /// Converts [lb] into this unit.
  double fromLb(double lb) =>
      this == WeightUnit.lb ? lb : lb / kPoundsPerKilogram;

  /// Converts [value], expressed in this unit, into [target].
  double convert(double value, WeightUnit target) => target.fromLb(toLb(value));

  /// The increment a UI should round to when *displaying* this unit.
  ///
  /// Display rounding is not load quantization: the plate math happens in the
  /// equipment's native unit (lb at Pennington) and only the label is converted,
  /// so a kg-preferring user still gets told to load a weight that exists.
  double get displayIncrement => this == WeightUnit.lb ? 0.5 : 0.1;
}

/// Rounds [value] to the nearest multiple of [increment].
///
/// Half-way values round away from zero. This is *display* rounding; see
/// `load_quantization.dart` for rounding to weights that physically exist.
double roundToIncrement(double value, double increment) {
  if (increment <= 0) {
    throw ArgumentError.value(increment, 'increment', 'Must be positive');
  }
  return (value / increment).roundToDouble() * increment;
}

/// A weight together with the unit it was expressed in.
final class Weight implements Comparable<Weight> {
  const Weight(this.value, this.unit);

  const Weight.lb(double value) : this(value, WeightUnit.lb);

  const Weight.kg(double value) : this(value, WeightUnit.kg);

  final double value;
  final WeightUnit unit;

  double get inLb => unit.toLb(value);

  double get inKg => unit.convert(value, WeightUnit.kg);

  /// This weight re-expressed in [target]. Round trips are lossless to within
  /// floating point: `Weight.lb(135).to(kg).to(lb)` is 135.
  Weight to(WeightUnit target) => Weight(unit.convert(value, target), target);

  /// This weight rounded for display in its own unit (0.5 lb / 0.1 kg).
  Weight rounded() =>
      Weight(roundToIncrement(value, unit.displayIncrement), unit);

  @override
  int compareTo(Weight other) => inLb.compareTo(other.inLb);

  @override
  bool operator ==(Object other) =>
      other is Weight && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => '$value ${unit.wireName}';
}

/// How hard a set was, reported as **either** RPE **or** RIR - never both.
///
/// Modelled as a sealed hierarchy rather than two nullable fields so that the
/// illegal state (`rpe: 8` alongside `rir: 4`, which contradict each other)
/// cannot be constructed at all. Absence of effort is the *field* being null,
/// not a third variant - a set logged with no rating is a real, common case and
/// every engine here handles it explicitly.
///
/// The two scales are one scale: **RPE = 10 - RIR** (Zourdos et al. 2016,
/// "Novel Resistance Training-Specific Rating of Perceived Exertion Scale
/// Measuring Repetitions in Reserve", J Strength Cond Res 30(1):267-275). RPE 10
/// is a set with nothing left, RPE 8 is two reps left, and so on.
sealed class Effort {
  const Effort();

  /// Reported RPE, 0-10. Throws [ArgumentError] outside that range.
  factory Effort.rpe(double value) = RpeEffort;

  /// Reported reps in reserve, 0 or more. Throws [ArgumentError] if negative.
  factory Effort.rir(int value) = RirEffort;

  /// Reps left in the tank implied by this rating.
  double get repsInReserve;

  /// RPE implied by this rating.
  double get rpe;

  /// How the app says this out loud: "RPE 7", "3 reps in reserve".
  String get label;
}

/// Rate of Perceived Exertion, 0-10.
final class RpeEffort extends Effort {
  factory RpeEffort(double value) {
    if (value.isNaN || value < 0 || value > 10) {
      throw ArgumentError.value(value, 'rpe', 'RPE must be between 0 and 10');
    }
    return RpeEffort._(value);
  }

  const RpeEffort._(this.value);

  final double value;

  @override
  double get rpe => value;

  @override
  double get repsInReserve => 10 - value;

  @override
  String get label => 'RPE ${formatTrimmed(value)}';

  @override
  bool operator ==(Object other) => other is RpeEffort && other.value == value;

  @override
  int get hashCode => Object.hash(RpeEffort, value);

  @override
  String toString() => label;
}

/// Reps in Reserve - how many more reps the lifter believed they had.
final class RirEffort extends Effort {
  factory RirEffort(int value) {
    if (value < 0) {
      throw ArgumentError.value(
        value,
        'rir',
        'Reps in reserve cannot be negative',
      );
    }
    return RirEffort._(value);
  }

  const RirEffort._(this.value);

  final int value;

  @override
  double get repsInReserve => value.toDouble();

  /// RPE below 0 is not a thing: 11+ reps in reserve clamps at RPE 0.
  @override
  double get rpe => (10 - value).clamp(0, 10).toDouble();

  @override
  String get label =>
      value == 1 ? '1 rep in reserve' : '$value reps in reserve';

  @override
  bool operator ==(Object other) => other is RirEffort && other.value == value;

  @override
  int get hashCode => Object.hash(RirEffort, value);

  @override
  String toString() => label;
}

/// Formats a number the way a coach would say it: `145`, not `145.0`.
///
/// Tolerant of floating point, so a converted 65.8 kg does not print as
/// "65.80".
String formatTrimmed(double value) {
  if ((value - value.roundToDouble()).abs() < 1e-9) {
    return value.toStringAsFixed(0);
  }
  final oneDecimal = value.toStringAsFixed(1);
  if ((double.parse(oneDecimal) - value).abs() < 1e-9) {
    return oneDecimal;
  }
  return value.toStringAsFixed(2);
}

/// Equipment the Rec Center has, per `docs/rec-center-equipment.md`.
///
/// `bodyweight` and `outdoor` cover the non-gym half of a plan (push-ups, runs,
/// hikes) where there is no external load to quantize.
enum EquipmentType {
  dumbbell('dumbbell'),
  barbell('barbell'),
  squatRack('squat_rack'),
  cableStation('cable_station'),
  latPulldown('lat_pulldown'),
  legExtension('leg_extension'),
  hamstringCurl('hamstring_curl'),
  benchPress('bench_press'),
  inclineBenchPress('incline_bench_press'),
  cableRow('cable_row'),
  backRow('back_row'),
  pecDeck('pec_deck'),
  rearDeltFly('rear_delt_fly'),
  tricepPushdown('tricep_pushdown'),
  bodyweight('bodyweight'),
  outdoor('outdoor');

  const EquipmentType(this.wireName);

  final String wireName;

  static EquipmentType? tryFromWireName(String wireName) {
    for (final type in values) {
      if (type.wireName == wireName) {
        return type;
      }
    }
    return null;
  }
}

/// One logged set - the row shape of `workout_logs`.
///
/// [weight] is kept in the [unit] the user typed; [weightLb] is what every
/// engine actually reads.
final class LoggedSet {
  LoggedSet({
    required this.exerciseId,
    required this.setIndex,
    required this.setType,
    required this.weight,
    required this.unit,
    required this.reps,
    required this.performedAt,
    this.effort,
    this.workoutId,
  }) {
    if (exerciseId.isEmpty) {
      throw ArgumentError.value(exerciseId, 'exerciseId', 'Must not be empty');
    }
    if (setIndex < 0) {
      throw ArgumentError.value(setIndex, 'setIndex', 'Must not be negative');
    }
    if (reps < 0) {
      throw ArgumentError.value(reps, 'reps', 'Must not be negative');
    }
    if (weight.isNaN || weight.isInfinite || weight < 0) {
      throw ArgumentError.value(
        weight,
        'weight',
        'Must be a finite, non-negative number',
      );
    }
  }

  /// `exercises.id` this set belongs to.
  final String exerciseId;

  /// 0-based position within the exercise for this session.
  final int setIndex;

  final SetType setType;

  /// As logged, in [unit]. Bodyweight work is legitimately `0`.
  final double weight;

  final WeightUnit unit;

  /// Reps actually completed. A failed set is `reps` below the target range,
  /// including `0`.
  final int reps;

  /// `null` when the user logged neither RPE nor RIR, which is allowed and
  /// common. Engines degrade to conservative behaviour rather than guessing a
  /// value the lifter never reported.
  final Effort? effort;

  final DateTime performedAt;

  /// `user_workouts.id` when the set came from a planned session. Sets without
  /// one are grouped into sessions by calendar day.
  final String? workoutId;

  /// The load in the canonical unit.
  double get weightLb => unit.toLb(weight);

  Weight get load => Weight(weight, unit);

  /// Tonnage contributed by this set: reps x load.
  double get tonnageLb => weightLb * reps;

  bool get countsAsVolume => setType.countsAsVolume;

  bool get drivesLoadProgression => setType.drivesLoadProgression;

  /// Calendar day of [performedAt], time stripped.
  DateTime get day =>
      DateTime(performedAt.year, performedAt.month, performedAt.day);

  /// Grouping key for "one session": the planned workout when there is one,
  /// otherwise the calendar day.
  String get sessionKey => workoutId ?? '${day.year}-${day.month}-${day.day}';

  @override
  String toString() =>
      'LoggedSet($exerciseId #$setIndex: '
      '${formatTrimmed(weight)}${unit.wireName} x $reps'
      '${effort == null ? '' : ' @ ${effort!.label}'})';
}

/// One exercise performed in one session: every set logged for it that day.
final class ExerciseSession {
  ExerciseSession(this.exerciseId, this.date, this.sets);

  final String exerciseId;

  /// Calendar day, time stripped.
  final DateTime date;

  /// Every set in the session, in logged order.
  final List<LoggedSet> sets;

  /// Straight working sets only - the ones that describe real capability.
  ///
  /// A set with zero reps stays in: failing to complete a single rep is the
  /// loudest signal in the history, and dropping it would make a total failure
  /// invisible to the progression engine.
  List<LoggedSet> get workingSets =>
      sets.where((set) => set.drivesLoadProgression).toList(growable: false);

  /// The heaviest working set; ties break toward the one with the most reps.
  LoggedSet? get topWorkingSet {
    LoggedSet? best;
    for (final set in workingSets) {
      if (best == null ||
          set.weightLb > best.weightLb ||
          (set.weightLb == best.weightLb && set.reps > best.reps)) {
        best = set;
      }
    }
    return best;
  }

  double? get topWorkingLoadLb => topWorkingSet?.weightLb;

  List<LoggedSet> get _setsAtTopLoad {
    final top = topWorkingLoadLb;
    if (top == null) {
      return const <LoggedSet>[];
    }
    return workingSets
        .where((set) => (set.weightLb - top).abs() < 1e-6)
        .toList(growable: false);
  }

  /// Fewest reps completed across the working sets at the session's top load.
  ///
  /// Conservative on purpose: finishing 12, 12, 8 of an 8-12 range is not "12
  /// reps at that weight", and reading it as such adds load the lifter has not
  /// earned.
  int? get repsAtTopLoad {
    final atTop = _setsAtTopLoad;
    if (atTop.isEmpty) {
      return null;
    }
    return atTop.map((set) => set.reps).reduce((a, b) => a < b ? a : b);
  }

  /// Hardest effort reported at the top load (the lowest reps in reserve), or
  /// `null` when the lifter rated none of those sets.
  Effort? get effortAtTopLoad {
    Effort? hardest;
    for (final set in _setsAtTopLoad) {
      final effort = set.effort;
      if (effort == null) {
        continue;
      }
      if (hardest == null || effort.repsInReserve < hardest.repsInReserve) {
        hardest = effort;
      }
    }
    return hardest;
  }

  /// Sets x reps x weight for everything that counts as volume.
  double get tonnageLb => sets
      .where((set) => set.countsAsVolume)
      .fold(0, (sum, set) => sum + set.tonnageLb);

  /// Number of sets that count as volume ("hard sets").
  int get hardSetCount => sets.where((set) => set.countsAsVolume).length;

  @override
  String toString() =>
      'ExerciseSession($exerciseId, '
      '${date.toIso8601String().split('T').first}, ${sets.length} sets)';
}

/// A user's logged sets for one exercise, over time.
///
/// Sets are sorted oldest-first and grouped into [sessions]. An empty history is
/// a first-class, expected case, not an error - see `progression.dart`, which
/// answers it with [NotEnoughData] rather than a guess.
final class ExerciseHistory {
  factory ExerciseHistory({
    required String exerciseId,
    required Iterable<LoggedSet> sets,
  }) {
    if (exerciseId.isEmpty) {
      throw ArgumentError.value(exerciseId, 'exerciseId', 'Must not be empty');
    }
    final ordered = sets.toList();
    for (final set in ordered) {
      if (set.exerciseId != exerciseId) {
        throw ArgumentError.value(
          set.exerciseId,
          'sets',
          'History for "$exerciseId" was handed a set for "${set.exerciseId}"',
        );
      }
    }
    ordered.sort((a, b) {
      final byTime = a.performedAt.compareTo(b.performedAt);
      return byTime != 0 ? byTime : a.setIndex.compareTo(b.setIndex);
    });
    return ExerciseHistory._(exerciseId, List.unmodifiable(ordered));
  }

  /// A lifter who has never performed this exercise.
  factory ExerciseHistory.empty(String exerciseId) =>
      ExerciseHistory(exerciseId: exerciseId, sets: const <LoggedSet>[]);

  ExerciseHistory._(this.exerciseId, this.sets);

  final String exerciseId;

  /// All logged sets, oldest first.
  final List<LoggedSet> sets;

  /// Sessions oldest first, grouped by planned workout or calendar day.
  List<ExerciseSession> get sessions {
    final grouped = <String, List<LoggedSet>>{};
    for (final set in sets) {
      grouped.putIfAbsent(set.sessionKey, () => <LoggedSet>[]).add(set);
    }
    final result = grouped.values
        .map(
          (group) => ExerciseSession(
            exerciseId,
            group.first.day,
            List.unmodifiable(group),
          ),
        )
        .toList();
    result.sort((a, b) => a.date.compareTo(b.date));
    return List.unmodifiable(result);
  }

  /// Sessions containing at least one straight working set - the only ones load
  /// progression can read.
  List<ExerciseSession> get workingSessions => sessions
      .where((session) => session.topWorkingSet != null)
      .toList(growable: false);

  bool get isEmpty => sets.isEmpty;

  bool get isNotEmpty => sets.isNotEmpty;

  @override
  String toString() =>
      'ExerciseHistory($exerciseId, ${sets.length} sets, '
      '${sessions.length} sessions)';
}

/// The rep range a set is programmed for, e.g. 8-12 for hypertrophy.
final class RepRange {
  const RepRange(this.min, this.max)
    : assert(min >= 1, 'A rep range starts at 1'),
      assert(max >= min, 'A rep range cannot end below where it starts');

  factory RepRange.exactly(int reps) => RepRange(reps, reps);

  final int min;
  final int max;

  bool contains(int reps) => reps >= min && reps <= max;

  /// Completed the top of the range - under double progression, the signal to
  /// add weight.
  bool isAtOrAboveTop(int reps) => reps >= max;

  /// Missed the bottom of the range - a failed set.
  bool isBelowBottom(int reps) => reps < min;

  @override
  bool operator ==(Object other) =>
      other is RepRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => min == max ? '$min' : '$min-$max';
}

/// One exercise in the catalog, as far as the training engines care.
final class ExerciseDefinition {
  const ExerciseDefinition({
    required this.id,
    required this.name,
    required this.equipment,
    required this.primaryMuscleGroups,
    this.secondaryMuscleGroups = const <MuscleGroup>[],
    this.unmappedRegions = const <UnmappedRegion>[],
  });

  final String id;
  final String name;
  final EquipmentType equipment;

  /// Movers that take the full share of the set's volume.
  final List<MuscleGroup> primaryMuscleGroups;

  /// Assisting movers, counted at a fractional share (see `volume.dart`).
  final List<MuscleGroup> secondaryMuscleGroups;

  /// Regions this exercise trains that the 3D model has no geometry for. Their
  /// volume is attributed through [UnmappedRegion.mapsTo] and also reported
  /// on its own, so nothing is silently dropped.
  final List<UnmappedRegion> unmappedRegions;
}

/// Lookup from `exercises.id` to its definition.
final class ExerciseCatalog {
  ExerciseCatalog(Iterable<ExerciseDefinition> exercises)
    : _byId = {for (final exercise in exercises) exercise.id: exercise};

  final Map<String, ExerciseDefinition> _byId;

  ExerciseDefinition? lookup(String exerciseId) => _byId[exerciseId];

  bool contains(String exerciseId) => _byId.containsKey(exerciseId);

  Iterable<ExerciseDefinition> get all => _byId.values;
}
