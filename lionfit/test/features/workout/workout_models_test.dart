import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/workout/data/workout_repository.dart';
import 'package:lionfit/features/workout/domain/workout_models.dart';

void main() {
  group('CatalogExercise.fromRow', () {
    final row = {
      'id': 'e1',
      'slug': 'seated_cable_row',
      'name': 'Seated Cable Row',
      'primary_muscle_groups': ['lats'],
      'secondary_muscle_groups': ['biceps', 'not_a_group'],
      'unmapped_muscle_groups': ['rhomboids'],
      'required_equipment': ['cable_row'],
      'movement_pattern': 'horizontal_pull',
      'is_outdoor': false,
      'notes': null,
    };

    test('parses muscle keys and skips unknown ones instead of crashing', () {
      final exercise = CatalogExercise.fromRow(row);
      expect(exercise.primaryMuscleGroups, [MuscleGroup.lats]);
      expect(exercise.secondaryMuscleGroups, [MuscleGroup.biceps]);
      expect(exercise.unmappedRegions, [UnmappedRegion.rhomboids]);
      expect(exercise.isActive, isTrue);
    });

    test(
      'reads is_active so retired exercises can be kept but not offered',
      () {
        final retired = CatalogExercise.fromRow({...row, 'is_active': false});
        expect(retired.isActive, isFalse);
      },
    );

    test('maps database equipment slugs onto the engine enum', () {
      expect(
        CatalogExercise.fromRow({
          ...row,
          'required_equipment': ['dumbbell_pair'],
        }).toDefinition().equipment,
        EquipmentType.dumbbell,
      );
      expect(
        CatalogExercise.fromRow({
          ...row,
          'required_equipment': ['leg_press'],
        }).toDefinition().equipment,
        EquipmentType.bodyweight,
      );
    });
  });

  group('SetRecord', () {
    final row = {
      'id': 's1',
      'workout_id': 'w1',
      'exercise_id': 'e1',
      'set_index': 2,
      'set_type': 'drop_set',
      'weight': 60,
      'unit': 'kg',
      'reps': 8,
      'rpe': 8.5,
      'rir': null,
      'performed_on': '2026-10-17',
      'performed_at': '2026-10-17T22:15:00+00:00',
    };

    test(
      'converts to the engine set: 0-based index, day from performed_on',
      () {
        final logged = SetRecord.fromRow(row).toLoggedSet();
        expect(logged.setIndex, 1);
        expect(logged.setType, SetType.dropSet);
        expect(logged.unit, WeightUnit.kg);
        expect(logged.day, DateTime(2026, 10, 17));
        expect(logged.effort!.rpe, 8.5);
      },
    );

    test('bodyweight sets have zero load, not null', () {
      final logged = SetRecord.fromRow({...row, 'weight': null}).toLoggedSet();
      expect(logged.weight, 0);
    });

    test('describeSet reads like a log line', () {
      expect(describeSet(SetRecord.fromRow(row)), '60 kg × 8 · RPE 8.5');
      expect(
        describeSet(
          SetRecord.fromRow({...row, 'weight': null, 'rpe': null, 'rir': 2}),
        ),
        'Bodyweight × 8 · 2 RIR',
      );
    });
  });

  test('isoDate pads and never carries a time', () {
    expect(isoDate(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
    expect(parseIsoDate('2026-03-07'), DateTime(2026, 3, 7));
  });
}
