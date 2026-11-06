import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/equipment_loads.dart';
import 'package:lionfit/core/training/load_quantization.dart';
import 'package:lionfit/core/training/models.dart';

/// The ranges below are rows of the Pennington equipment list.
void main() {
  group('stack', () {
    const legExtension = EquipmentLoadSpec(
      kind: LoadKind.stack,
      min: 12.5,
      max: 200,
      step: 12.5,
    );

    test('every pin from min to max, without float drift', () {
      final loads = legExtension.loadsLb();
      expect(loads.first, 12.5);
      expect(loads.last, 200);
      expect(loads, hasLength(16));
      expect(loads, contains(112.5));
    });

    test('rounds a suggestion to a real pin', () {
      final q = legExtension.toQuantizer(label: 'Leg Extension');
      expect(q.quantize(105), 100);
      expect(q.quantize(105, direction: RoundingDirection.up), 112.5);
      expect(q.stepUp(100), 112.5);
    });

    test('a 20 lb leg-press stack has no 10 lb jumps', () {
      const legPress = EquipmentLoadSpec(
        kind: LoadKind.stack,
        min: 0,
        max: 400,
        step: 20,
      );
      final q = legPress.toQuantizer(label: 'Leg Press');
      expect(q.quantize(150, direction: RoundingDirection.down), 140);
      expect(q.stepUp(140), 160);
      expect(legPress.smallestJumpLb, 20);
    });
  });

  group('plates', () {
    const bench = EquipmentLoadSpec(
      kind: LoadKind.plates,
      min: 45,
      max: 600,
      step: 2.5,
    );

    test('the smallest jump is two of the smallest plate', () {
      expect(bench.smallestJumpLb, 5);
      final loads = bench.loadsLb();
      expect(loads.take(3), [45, 50, 55]);
      expect(loads, isNot(contains(47.5)));
      expect(loads.last, 600);
    });
  });

  group('fixed set', () {
    test('includes the heaviest implement when the step misses it', () {
      // The list: kettlebells 3 kg to 24 kg in 2 kg steps.
      const bells = EquipmentLoadSpec(
        kind: LoadKind.fixedSet,
        min: 3,
        max: 24,
        step: 2,
        unit: WeightUnit.kg,
      );
      final loads = bells.loadsLb();
      expect(loads.first, closeTo(6.61, 0.01));
      expect(loads.last, closeTo(52.91, 0.01));
      expect(loads, hasLength(12));
    });

    test('explicit denominations win over the computed range', () {
      const dumbbells = EquipmentLoadSpec(
        kind: LoadKind.fixedSet,
        min: 5,
        max: 125,
        step: 5,
        explicitLoadsLb: [10, 5, 15],
      );
      expect(dumbbells.loadsLb(), [5, 10, 15]);
    });
  });

  test('wire names round-trip and unknowns are null', () {
    for (final kind in LoadKind.values) {
      expect(LoadKind.tryFromWireName(kind.wireName), kind);
    }
    expect(LoadKind.tryFromWireName('hydraulic'), isNull);
    expect(LoadKind.tryFromWireName(null), isNull);
  });
}
