import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';

/// The muscle-group vocabulary is a three-way contract between:
///   1. the GLB material names in assets/muscleAnatomy.glb
///   2. the Postgres `muscle_group` enum in supabase/migrations/
///   3. `MuscleGroup` in lib/core/training/models.dart
///
/// If any one drifts, the 3D map stops coloring and nothing throws — the
/// lookup just misses. These tests pin the Dart side. Run
/// `node tool/inspect_glb.js assets/muscleAnatomy.glb` to re-verify the asset
/// side, and keep the SQL enum in lockstep.
void main() {
  /// Verified against the GLB's 16 colorable materials and the Postgres enum.
  const canonical = <String>{
    'abs',
    'adductors',
    'biceps',
    'calves',
    'chest_lower',
    'chest_upper',
    'delts_front',
    'delts_rear',
    'delts_side',
    'forearms',
    'glutes',
    'hamstrings',
    'lats',
    'quads',
    'traps_upper',
    'triceps',
  };

  test('MuscleGroup has exactly the 16 renderable groups', () {
    expect(MuscleGroup.values.length, 16);
    expect(MuscleGroup.values.map((g) => g.wireName).toSet(), canonical);
  });

  test('wire names are snake_case and never collide', () {
    final names = MuscleGroup.values.map((g) => g.wireName).toList();
    expect(names.toSet().length, names.length, reason: 'duplicate wire name');
    for (final name in names) {
      expect(
        RegExp(r'^[a-z]+(_[a-z]+)*$').hasMatch(name),
        isTrue,
        reason: name,
      );
    }
  });

  test('unmapped regions stay OUT of MuscleGroup', () {
    // These four have no geometry in the GLB. Promoting one into MuscleGroup
    // would make the map query a material that does not exist.
    for (final region in UnmappedRegion.values) {
      expect(
        canonical.contains(region.wireName),
        isFalse,
        reason: '${region.wireName} must not be a renderable MuscleGroup',
      );
    }
  });

  test('unmapped regions match the Postgres unmapped_muscle_group enum', () {
    expect(UnmappedRegion.values.map((r) => r.wireName).toSet(), {
      'erector_spinae',
      'obliques',
      'rhomboids',
      'tibialis_anterior',
    });
  });

  test('every unmapped region falls back to a renderable group', () {
    for (final region in UnmappedRegion.values) {
      expect(canonical.contains(region.mapsTo.wireName), isTrue);
    }
  });
}
