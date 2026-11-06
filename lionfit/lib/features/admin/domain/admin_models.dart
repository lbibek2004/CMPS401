/// What the admin tools edit, and the rules a row must pass before it is
/// sent. The database re-checks all of it (constraints + RLS); these exist so
/// the form can say what is wrong before a round trip. Pure Dart.
library;

import '../../../core/training/models.dart';

/// `public.movement_pattern`, in the enum's order (migration 0001).
const kMovementPatterns = [
  'squat',
  'hinge',
  'lunge',
  'horizontal_push',
  'vertical_push',
  'horizontal_pull',
  'vertical_pull',
  'carry',
  'isolation',
  'core',
  'cardio',
];

String movementPatternLabel(String pattern) {
  final words = pattern.split('_');
  return [
    for (final (i, w) in words.indexed)
      i == 0 ? '${w[0].toUpperCase()}${w.substring(1)}' : w,
  ].join(' ');
}

/// The two equipment sentinels an exercise may require that are not rows.
const kEquipmentSentinels = ['bodyweight', 'outdoor'];

/// Same rule as the `exercises_slug_format` / `rec_center_equipment_type_format`
/// checks: lowercase letter first, then lowercase letters, digits, `_`.
final RegExp kSlugPattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// "Incline DB Press (45°)" -> "incline_db_press_45".
String slugify(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp('_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (slug.isEmpty) return '';
  // Must start with a letter.
  return RegExp('^[a-z]').hasMatch(slug) ? slug : 'x_$slug';
}

/// A new or edited `exercises` row, as the admin form holds it.
final class ExerciseDraft {
  const ExerciseDraft({
    required this.name,
    required this.slug,
    required this.primary,
    required this.secondary,
    required this.equipment,
    required this.movementPattern,
    this.isOutdoor = false,
    this.isActive = true,
    this.notes,
  });

  final String name;
  final String slug;
  final Set<MuscleGroup> primary;
  final Set<MuscleGroup> secondary;
  final Set<String> equipment;
  final String movementPattern;
  final bool isOutdoor;
  final bool isActive;
  final String? notes;

  /// Null when the row is fine; otherwise the first thing to fix.
  String? problem({required Set<String> knownEquipment, bool isNew = false}) {
    if (name.trim().isEmpty) return 'Give the exercise a name.';
    if (isNew && !kSlugPattern.hasMatch(slug)) {
      return 'The ID must start with a letter and use only a-z, 0-9 and _.';
    }
    if (primary.isEmpty) return 'Pick at least one primary muscle.';
    if (!kMovementPatterns.contains(movementPattern)) {
      return 'Pick a movement pattern.';
    }
    if (equipment.isEmpty) {
      return 'Pick the equipment it needs (or Bodyweight / Outdoor).';
    }
    for (final slug in equipment) {
      if (!knownEquipment.contains(slug) &&
          !kEquipmentSentinels.contains(slug)) {
        return 'Unknown equipment: $slug.';
      }
    }
    return null;
  }

  /// Columns for insert/update. The slug is only sent for a new row - it is
  /// the stable ID other code refers to, so it is not editable afterwards.
  Map<String, dynamic> toRow({bool includeSlug = false}) => {
    if (includeSlug) 'slug': slug,
    'name': name.trim(),
    'primary_muscle_groups': [for (final g in primary) g.wireName],
    // A group cannot be both primary and secondary.
    'secondary_muscle_groups': [
      for (final g in secondary)
        if (!primary.contains(g)) g.wireName,
    ],
    'required_equipment': equipment.toList()..sort(),
    'movement_pattern': movementPattern,
    'is_outdoor': isOutdoor,
    'is_active': isActive,
    'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
  };
}
