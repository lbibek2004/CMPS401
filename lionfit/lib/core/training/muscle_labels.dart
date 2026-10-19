/// Human labels for the 16 muscle group keys.
///
/// The wire names (`chest_lower`) are a contract with the database and the
/// GLB; these are what a student reads. Pure Dart.
library;

import 'models.dart';

String muscleGroupLabel(MuscleGroup group) => switch (group) {
  MuscleGroup.abs => 'Abs',
  MuscleGroup.adductors => 'Adductors',
  MuscleGroup.biceps => 'Biceps',
  MuscleGroup.calves => 'Calves',
  MuscleGroup.chestLower => 'Lower chest',
  MuscleGroup.chestUpper => 'Upper chest',
  MuscleGroup.deltsFront => 'Front delts',
  MuscleGroup.deltsRear => 'Rear delts',
  MuscleGroup.deltsSide => 'Side delts',
  MuscleGroup.forearms => 'Forearms',
  MuscleGroup.glutes => 'Glutes',
  MuscleGroup.hamstrings => 'Hamstrings',
  MuscleGroup.lats => 'Lats',
  MuscleGroup.quads => 'Quads',
  MuscleGroup.trapsUpper => 'Upper traps',
  MuscleGroup.triceps => 'Triceps',
};

String unmappedRegionLabel(UnmappedRegion region) => switch (region) {
  UnmappedRegion.erectorSpinae => 'Lower back',
  UnmappedRegion.obliques => 'Obliques',
  UnmappedRegion.rhomboids => 'Rhomboids',
  UnmappedRegion.tibialisAnterior => 'Shins',
};
