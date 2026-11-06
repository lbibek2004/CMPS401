// Every suggestion has to be a weight the Rec Center physically owns. These
// tests are the ones that catch "load 42.5 lb" on a rack that jumps 40 to 45.
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/load_quantization.dart';
import 'package:lionfit/core/training/models.dart';

void main() {
  group('the Pennington dumbbell rack', () {
    final rack = DumbbellQuantizer();

    test('snaps a weight that does not exist to one that does', () {
      // The rack goes 40 -> 45. 42.5 is not a dumbbell anyone can pick up.
      expect(rack.quantize(42.5), 40);
      expect(rack.quantize(42.5, direction: RoundingDirection.down), 40);
      expect(rack.quantize(42.5, direction: RoundingDirection.up), 45);
      expect(rack.loads, isNot(contains(42.5)));
    });

    test('breaks an exact tie downward, toward the weight already earned', () {
      expect(rack.quantize(42.5), 40);
      expect(rack.quantize(47.5), 45);
    });

    test('is the written Pennington rack: 5 to 125 lb in 5 lb steps', () {
      expect(rack.loads.take(4), [5, 10, 15, 20]);
      expect(rack.loads, hasLength(25));
      expect(rack.minimumLoadLb, 5);
      expect(rack.maximumLoadLb, 125);
    });

    test(
      'clamps to the rack rather than inventing a weight off either end',
      () {
        expect(rack.quantize(0.25), 5);
        expect(rack.quantize(400), 125);
        expect(rack.stepUp(125), 125);
        expect(rack.stepDown(5), 5);
      },
    );

    test('steps to the next dumbbell that actually exists', () {
      expect(rack.stepUp(40), 45);
      expect(rack.stepDown(40), 35);
      expect(rack.stepUp(5), 10);
      expect(rack.stepDown(10), 5);
    });

    test(
      'comes from the written equipment list, so it is not an assumption',
      () {
        expect(rack.isUnverifiedAssumption, isFalse);
        expect(rack.description, contains('Pennington dumbbell rack'));
      },
    );

    test('accepts a different rack when the floor walk corrects it', () {
      final corrected = DumbbellQuantizer(
        rackLb: const [5, 10, 15, 20, 25, 30],
      );
      expect(corrected.quantize(42.5), 30);
      expect(corrected.quantize(12), 10);
    });
  });

  group('a barbell', () {
    final barbell = BarbellQuantizer();

    test('only makes loads that are the bar plus symmetric plate pairs', () {
      for (final load in barbell.loads) {
        final perSide = (load - barbell.barWeightLb) / 2;
        expect(
          perSide * 4,
          closeTo((perSide * 4).roundToDouble(), 1e-9),
          reason: '$load lb must divide into two equal sides',
        );
        expect(perSide, greaterThanOrEqualTo(0));
      }
      expect(barbell.loads, contains(45.0), reason: 'the empty bar');
      expect(barbell.loads, contains(135.0));
      expect(barbell.loads, contains(145.0));
      expect(
        barbell.loads,
        isNot(contains(47.5)),
        reason: 'that would need a 1.25 lb plate on one side only',
      );
    });

    test('lands a half-plate suggestion on a real total', () {
      expect(barbell.quantize(147.0), 145);
      expect(barbell.quantize(147.0, direction: RoundingDirection.up), 150);
      expect(barbell.quantize(142.5), 140, reason: 'a tie rounds down');
    });

    test('tells the lifter what to hang on each side', () {
      expect(barbell.platesPerSide(145), {45.0: 1, 5.0: 1});
      expect(barbell.platesPerSide(225), {45.0: 2});
      expect(barbell.platesPerSide(45), isEmpty);
    });

    test(
      'flags its plate set as an assumption instead of stating it as fact',
      () {
        expect(barbell.isUnverifiedAssumption, isTrue);
        expect(barbell.description, contains('ASSUMED'));
        expect(barbell.plateDenominationsLb, kAssumedPlateDenominationsLb);
        expect(barbell.barWeightLb, kAssumedBarbellWeightLb);
        expect(
          kLoadQuantizationAssumptions.any((note) => note.contains('Plate')),
          isTrue,
          reason: 'the open question has to be surfaceable in the UI',
        );
      },
    );

    test('changes every suggestion when the real plate set has no 2.5s', () {
      // This is exactly why the denominations are a parameter: without 2.5 lb
      // plates the smallest possible jump doubles.
      final noLightPlates = BarbellQuantizer(
        plateDenominationsLb: const [45, 25, 10, 5],
        denominationsAreVerified: true,
      );
      expect(noLightPlates.smallestIncrementLb, 10);
      expect(noLightPlates.loads, isNot(contains(50.0)));
      expect(noLightPlates.quantize(60), 55);
      expect(noLightPlates.quantize(60, direction: RoundingDirection.up), 65);
      expect(noLightPlates.isUnverifiedAssumption, isFalse);
      expect(noLightPlates.description, isNot(contains('ASSUMED')));
    });

    test('accepts a different bar weight', () {
      final womensBar = BarbellQuantizer(barWeightLb: 35);
      expect(womensBar.loads, contains(35.0));
      expect(womensBar.quantize(100), 100);
      expect(womensBar.quantize(102), 100);
    });

    test('refuses a plate set it cannot build anything from', () {
      expect(
        () => BarbellQuantizer(plateDenominationsLb: const []),
        throwsArgumentError,
      );
    });
  });

  group('a selectorized stack', () {
    test('snaps to the assumed pin spacing and says that it is assumed', () {
      final stack = MachineStackQuantizer();
      expect(stack.quantize(47), 50);
      expect(stack.quantize(47, direction: RoundingDirection.down), 40);
      expect(stack.incrementLb, kAssumedStackIncrementLb);
      expect(stack.isUnverifiedAssumption, isTrue);
      expect(stack.description, contains('ASSUMED'));
    });

    test('takes a measured spacing once a machine has been checked', () {
      final measured = MachineStackQuantizer(
        incrementLb: 15,
        minimumLb: 15,
        maximumLb: 300,
        machineName: 'Lat pulldown',
        spacingIsVerified: true,
      );
      expect(measured.quantize(100), 105);
      expect(measured.isUnverifiedAssumption, isFalse);
      expect(measured.description, 'Lat pulldown (15 lb plates)');
    });
  });

  group('bodyweight and outdoor work', () {
    const nothingToLoad = BodyweightQuantizer();

    test(
      'passes a load straight through because there is nothing to snap to',
      () {
        expect(nothingToLoad.quantize(173.2), 173.2);
        expect(nothingToLoad.quantize(0), 0);
        expect(
          nothingToLoad.stepUp(0),
          0,
          reason: 'bodyweight work progresses in reps, not pounds',
        );
      },
    );
  });

  group('the registry', () {
    final registry = LoadQuantizerRegistry.pennington();

    test('gives each equipment type its own rounding table', () {
      expect(registry.quantize(42.5, EquipmentType.dumbbell), 40);
      expect(registry.quantize(147, EquipmentType.benchPress), 145);
      expect(registry.quantize(147, EquipmentType.squatRack), 145);
      expect(registry.quantize(47, EquipmentType.latPulldown), 50);
      expect(registry.quantize(173.2, EquipmentType.outdoor), 173.2);
    });

    test('admits that some of its tables are still guesses', () {
      expect(registry.hasUnverifiedAssumptions, isTrue);
      expect(kLoadQuantizationAssumptions, isNotEmpty);
    });

    test('lets one machine be overridden without touching the engine', () {
      final withMeasuredPulldown = LoadQuantizerRegistry.pennington(
        overrides: {
          EquipmentType.latPulldown: MachineStackQuantizer(
            incrementLb: 15,
            minimumLb: 15,
            machineName: 'Lat pulldown',
            spacingIsVerified: true,
          ),
        },
      );
      expect(
        withMeasuredPulldown.quantize(100, EquipmentType.latPulldown),
        105,
      );
      // Everything else keeps the shared default.
      expect(withMeasuredPulldown.quantize(47, EquipmentType.cableRow), 50);
    });

    test('covers every equipment type the catalog can name', () {
      for (final equipment in EquipmentType.values) {
        expect(registry.forEquipment(equipment), isNotNull);
      }
    });
  });
}
