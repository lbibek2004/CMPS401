import 'package:lionfit/core/training/equipment_loads.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/workout/domain/equipment_item.dart';
import 'package:lionfit/features/workout/domain/workout_models.dart';

/// A small slice of the real catalog and equipment list, shared by the coach
/// tests.
const bench = CatalogExercise(
  id: 'bench',
  slug: 'barbell_bench_press',
  name: 'Barbell Bench Press',
  primaryMuscleGroups: [MuscleGroup.chestLower],
  secondaryMuscleGroups: [MuscleGroup.triceps, MuscleGroup.deltsFront],
  requiredEquipment: ['bench_press'],
  movementPattern: 'horizontal_push',
);
const legExtension = CatalogExercise(
  id: 'legext',
  slug: 'leg_extension',
  name: 'Leg Extension',
  primaryMuscleGroups: [MuscleGroup.quads],
  requiredEquipment: ['leg_extension'],
  movementPattern: 'isolation',
);
const rotaryCalf = CatalogExercise(
  id: 'calf',
  slug: 'rotary_calf_raise',
  name: 'Rotary Calf Raise',
  primaryMuscleGroups: [MuscleGroup.calves],
  requiredEquipment: ['rotary_calf'],
  movementPattern: 'isolation',
);
const seatedCalf = CatalogExercise(
  id: 'scalf',
  slug: 'seated_calf_raise',
  name: 'Seated Calf Raise',
  primaryMuscleGroups: [MuscleGroup.calves],
  requiredEquipment: ['seated_calf_raise'],
  movementPattern: 'isolation',
);
const pushUp = CatalogExercise(
  id: 'pushup',
  slug: 'push_up',
  name: 'Push-Up',
  primaryMuscleGroups: [MuscleGroup.chestLower],
  secondaryMuscleGroups: [MuscleGroup.triceps],
  requiredEquipment: ['bodyweight'],
  movementPattern: 'horizontal_push',
);
const cableRow = CatalogExercise(
  id: 'row',
  slug: 'seated_cable_row',
  name: 'Seated Cable Row',
  primaryMuscleGroups: [MuscleGroup.lats],
  secondaryMuscleGroups: [MuscleGroup.biceps],
  unmappedRegions: [UnmappedRegion.rhomboids],
  requiredEquipment: ['cable_row'],
  movementPattern: 'horizontal_pull',
);
const treadmill = CatalogExercise(
  id: 'tread',
  slug: 'treadmill_run',
  name: 'Treadmill Run',
  primaryMuscleGroups: [MuscleGroup.quads, MuscleGroup.calves],
  requiredEquipment: ['treadmill'],
  movementPattern: 'cardio',
);
const outdoorRun = CatalogExercise(
  id: 'run',
  slug: 'outdoor_easy_run',
  name: 'Outdoor Easy Run',
  primaryMuscleGroups: [MuscleGroup.quads, MuscleGroup.calves],
  requiredEquipment: ['outdoor'],
  movementPattern: 'cardio',
  isOutdoor: true,
);
const retiredSquat = CatalogExercise(
  id: 'squat',
  slug: 'barbell_back_squat',
  name: 'Barbell Back Squat',
  primaryMuscleGroups: [MuscleGroup.quads],
  requiredEquipment: ['squat_rack'],
  movementPattern: 'squat',
  isActive: false,
);

const catalog = [
  bench,
  legExtension,
  rotaryCalf,
  seatedCalf,
  pushUp,
  cableRow,
  treadmill,
  outdoorRun,
  retiredSquat,
];

final inventory = EquipmentInventory(const [
  EquipmentItem(
    slug: 'bench_press',
    label: 'Flat Barbell Bench Press',
    quantity: 2,
    loadSpec: EquipmentLoadSpec(
      kind: LoadKind.plates,
      min: 45,
      max: 600,
      step: 2.5,
    ),
  ),
  EquipmentItem(
    slug: 'leg_extension',
    label: 'Leg Extension',
    quantity: 2,
    loadSpec: EquipmentLoadSpec(
      kind: LoadKind.stack,
      min: 12.5,
      max: 200,
      step: 12.5,
    ),
  ),
  EquipmentItem(
    slug: 'rotary_calf',
    label: 'Rotary Calf Machine',
    quantity: 2,
    loadSpec: EquipmentLoadSpec(
      kind: LoadKind.stack,
      min: 10,
      max: 405,
      step: 5,
    ),
  ),
  EquipmentItem(
    slug: 'seated_calf_raise',
    label: 'Seated Calf Raise',
    quantity: 1,
    status: EquipmentStatus.outOfService,
  ),
  EquipmentItem(
    slug: 'cable_row',
    label: 'Seated Cable Row',
    quantity: 2,
    loadSpec: EquipmentLoadSpec(
      kind: LoadKind.stack,
      min: 10,
      max: 295,
      step: 5,
    ),
  ),
  EquipmentItem(slug: 'treadmill', label: 'Treadmill', quantity: 16),
  EquipmentItem(slug: 'squat_rack', label: 'Squat Rack', quantity: 0),
]);

int _ids = 0;

SetRecord logged(
  CatalogExercise exercise, {
  required DateTime on,
  double? lb,
  required int reps,
  int index = 1,
  SetType type = SetType.working,
  double? rpe,
  int? rir,
}) => SetRecord(
  id: 'set${_ids++}',
  workoutId: 'w-${on.toIso8601String()}',
  exerciseId: exercise.id,
  setIndex: index,
  setType: type,
  unit: WeightUnit.lb,
  weight: lb,
  reps: reps,
  rpe: rpe,
  rir: rir,
  performedOn: on,
);
