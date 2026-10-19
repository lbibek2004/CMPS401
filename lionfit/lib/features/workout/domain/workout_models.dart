/// Row shapes for `exercises`, `user_workouts` and `workout_logs`, plus the
/// conversion into the training engine's types.
///
/// Parsing lives here, not in widgets, so a schema change breaks a unit test
/// instead of a screen.
library;

import '../../../core/training/models.dart';

/// One row of the `exercises` catalog.
final class CatalogExercise {
  const CatalogExercise({
    required this.id,
    required this.slug,
    required this.name,
    required this.primaryMuscleGroups,
    this.secondaryMuscleGroups = const [],
    this.unmappedRegions = const [],
    this.requiredEquipment = const [],
    this.movementPattern = '',
    this.isOutdoor = false,
    this.notes,
  });

  factory CatalogExercise.fromRow(Map<String, dynamic> row) => CatalogExercise(
    id: row['id'] as String,
    slug: row['slug'] as String,
    name: row['name'] as String,
    // tryFromWireName + whereType: an enum value added on the server before
    // the app ships an update is skipped, not a crash.
    primaryMuscleGroups: _groups(row['primary_muscle_groups']),
    secondaryMuscleGroups: _groups(row['secondary_muscle_groups']),
    unmappedRegions: [
      for (final key in (row['unmapped_muscle_groups'] as List?) ?? const [])
        ...UnmappedRegion.values.where((region) => region.wireName == key),
    ],
    requiredEquipment: [
      for (final slug in (row['required_equipment'] as List?) ?? const [])
        slug as String,
    ],
    movementPattern: (row['movement_pattern'] as String?) ?? '',
    isOutdoor: (row['is_outdoor'] as bool?) ?? false,
    notes: row['notes'] as String?,
  );

  final String id;
  final String slug;
  final String name;
  final List<MuscleGroup> primaryMuscleGroups;
  final List<MuscleGroup> secondaryMuscleGroups;
  final List<UnmappedRegion> unmappedRegions;

  /// `rec_center_equipment.equipment_type` slugs.
  final List<String> requiredEquipment;
  final String movementPattern;
  final bool isOutdoor;
  final String? notes;

  /// True for rows added by the demo-data migration (0008). Their equipment
  /// is placeholder data, not a confirmed Pennington inventory item.
  bool get isDemoData => notes?.startsWith('DEMO') ?? false;

  /// Bodyweight sets have no load to enter.
  bool get isBodyweightOnly =>
      requiredEquipment.isNotEmpty &&
      requiredEquipment.every((e) => e == 'bodyweight' || e == 'outdoor');

  /// Every group this exercise touches, primary first.
  List<MuscleGroup> get allMuscleGroups => [
    ...primaryMuscleGroups,
    ...secondaryMuscleGroups.where((g) => !primaryMuscleGroups.contains(g)),
  ];

  /// The engine's view of this exercise. Only the muscle mapping matters to
  /// the volume math; equipment is a best-effort match to the engine's
  /// [EquipmentType], falling back to bodyweight for gear it does not model.
  ExerciseDefinition toDefinition() => ExerciseDefinition(
    id: id,
    name: name,
    equipment: _engineEquipment(requiredEquipment),
    primaryMuscleGroups: primaryMuscleGroups,
    secondaryMuscleGroups: secondaryMuscleGroups,
    unmappedRegions: unmappedRegions,
  );

  static List<MuscleGroup> _groups(Object? raw) => [
    for (final key in (raw as List?) ?? const [])
      ?MuscleGroup.tryFromWireName(key as String),
  ];

  /// The database slugs and the engine's enum predate each other; these are
  /// the three that differ by name.
  static const _equipmentAliases = {
    'dumbbell_pair': EquipmentType.dumbbell,
    'adjustable_cable_station': EquipmentType.cableStation,
    'pec_deck_fly': EquipmentType.pecDeck,
    'olympic_barbell': EquipmentType.barbell,
  };

  static EquipmentType _engineEquipment(List<String> slugs) {
    for (final slug in slugs) {
      final match =
          _equipmentAliases[slug] ?? EquipmentType.tryFromWireName(slug);
      if (match != null) return match;
    }
    return EquipmentType.bodyweight;
  }
}

ExerciseCatalog catalogOf(Iterable<CatalogExercise> exercises) =>
    ExerciseCatalog(exercises.map((exercise) => exercise.toDefinition()));

/// One row of `workout_logs` - one performed set.
final class SetRecord {
  const SetRecord({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.setIndex,
    required this.setType,
    required this.unit,
    required this.performedOn,
    this.weight,
    this.reps,
    this.rpe,
    this.rir,
    this.performedAt,
  });

  factory SetRecord.fromRow(Map<String, dynamic> row) => SetRecord(
    id: row['id'] as String,
    workoutId: row['workout_id'] as String,
    exerciseId: row['exercise_id'] as String,
    setIndex: (row['set_index'] as num).toInt(),
    setType: setTypeFromWire(row['set_type'] as String? ?? 'working'),
    weight: (row['weight'] as num?)?.toDouble(),
    unit: (row['unit'] as String?) == 'kg' ? WeightUnit.kg : WeightUnit.lb,
    reps: (row['reps'] as num?)?.toInt(),
    rpe: (row['rpe'] as num?)?.toDouble(),
    rir: (row['rir'] as num?)?.toInt(),
    performedOn: parseIsoDate(row['performed_on'] as String),
    performedAt: row['performed_at'] == null
        ? null
        : DateTime.parse(row['performed_at'] as String).toLocal(),
  );

  final String id;
  final String workoutId;
  final String exerciseId;

  /// 1-based, as stored.
  final int setIndex;
  final SetType setType;

  /// As entered; null for bodyweight.
  final double? weight;
  final WeightUnit unit;
  final int? reps;
  final double? rpe;
  final int? rir;

  /// The session's calendar day - what the muscle map buckets by.
  final DateTime performedOn;
  final DateTime? performedAt;

  /// The engine's view of this set. Bucketed by [performedOn], not the
  /// wall-clock time, so the map agrees with the session's calendar day.
  LoggedSet toLoggedSet() => LoggedSet(
    exerciseId: exerciseId,
    setIndex: setIndex - 1,
    setType: setType,
    weight: weight ?? 0,
    unit: unit,
    reps: reps ?? 0,
    performedAt: performedOn,
    workoutId: workoutId,
    effort: rpe != null
        ? Effort.rpe(rpe!)
        : rir != null
        ? Effort.rir(rir!)
        : null,
  );
}

/// What the logger sends for a new set. user_id and performed_on are not
/// here on purpose: the database copies both from the parent session.
final class NewSet {
  const NewSet({
    required this.exerciseId,
    required this.setType,
    required this.unit,
    this.weight,
    this.reps,
    this.rpe,
    this.rir,
  });

  final String exerciseId;
  final SetType setType;
  final WeightUnit unit;
  final double? weight;
  final int? reps;
  final double? rpe;
  final int? rir;
}

SetType setTypeFromWire(String wire) => SetType.values.firstWhere(
  (type) => type.wireName == wire,
  orElse: () => SetType.working,
);

String setTypeLabel(SetType type) => switch (type) {
  SetType.warmUp => 'Warm-up',
  SetType.working => 'Working',
  SetType.dropSet => 'Drop set',
  SetType.superSet => 'Superset',
};

/// `yyyy-mm-dd` for a local calendar day. The database column is a plain
/// `date`; sending a timestamp would let a UTC offset move the session.
String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime parseIsoDate(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

DateTime calendarDay(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);
