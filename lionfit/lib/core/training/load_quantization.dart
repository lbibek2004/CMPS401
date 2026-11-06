/// Snapping a suggested load to a weight that **physically exists** at the
/// Pennington Student Activity Center.
///
/// This is not a rounding detail, it is the difference between a recommendation
/// the user can act on and one they cannot. The dumbbell rack jumps 40 -> 45; a
/// suggestion of 42.5 lb is a bug the user feels the moment they reach for it.
///
/// Every quantizer works in **pounds**, the canonical unit, because that is the
/// unit the equipment is actually labelled in. A kg-preferring user gets the
/// same physical weight with a converted label - we never quantize in kg and
/// hand back a weight no rack has.
///
/// ## What is verified and what is assumed
///
/// | Equipment | Source | Confidence |
/// | --- | --- | --- |
/// | Dumbbells 5-125 lb in 5 lb steps | Pennington equipment list (2026-10-19) | written list |
/// | Barbell bar weight (45 lb) | the list's 45 lb minimum on every bar station | written list |
/// | Plate denominations (45/35/25/10/5/2.5) | assumption | the list gives only the smallest plate (2.5 lb) |
/// | Selectorized stack spacing (10 lb) | fallback only | real machines use `equipment_loads.dart` |
///
/// The per-machine ranges from the equipment list live in `equipment_loads.dart`
/// and are what the app actually rounds to; the registry below is the fallback
/// for equipment with no load columns.
///
/// Everything unconfirmed is an **injectable parameter with a named default**,
/// and every quantizer reports [LoadQuantizer.isUnverifiedAssumption] so a
/// screen can mark the number provisional instead of implying it was measured.
/// See [kLoadQuantizationAssumptions] for the list to surface after the floor
/// walk.
///
/// ## Directional rounding
///
/// Rounding has a direction because the user's intent has one:
///
/// * [RoundingDirection.down] on a progression not yet earned - a held or
///   reduced load should never land heavier than the math asked for.
/// * [RoundingDirection.up] when they beat the target comfortably - they earned
///   the jump, give them the real next weight.
/// * [RoundingDirection.nearest] for everything else; ties break **down**.
library;

import 'models.dart';

const double _tolerance = 1e-6;

/// Which way to round when the exact weight does not exist.
enum RoundingDirection { down, up, nearest }

/// Rounds a desired load to a weight the gym actually has.
abstract interface class LoadQuantizer {
  /// Human-readable description of the equipment and where its numbers came
  /// from, e.g. "Pennington dumbbell rack (5-125 lb)".
  String get description;

  /// `true` when this quantizer's denominations are assumed rather than
  /// verified on the floor. Surface it; do not hide it.
  bool get isUnverifiedAssumption;

  /// Lightest load this equipment can be set to.
  double get minimumLoadLb;

  /// Heaviest load this equipment can be set to.
  double get maximumLoadLb;

  /// Snaps [desiredLb] to an existing weight.
  double quantize(
    double desiredLb, {
    RoundingDirection direction = RoundingDirection.nearest,
  });

  /// The next real weight above [fromLb] - the smallest increase this equipment
  /// can express. Returns [maximumLoadLb] when there is nothing heavier.
  double stepUp(double fromLb);

  /// The next real weight below [fromLb]. Returns [minimumLoadLb] when there is
  /// nothing lighter.
  double stepDown(double fromLb);
}

/// A quantizer backed by an explicit list of weights that exist.
///
/// Dumbbell racks, selectorized stacks, and barbell plate combinations all
/// reduce to "here are the loads you can actually set", so they all share this
/// implementation and differ only in how the list is built.
class DiscreteLoadQuantizer implements LoadQuantizer {
  DiscreteLoadQuantizer(
    Iterable<double> loadsLb, {
    required this.description,
    this.isUnverifiedAssumption = false,
  }) : loads = _normalize(loadsLb);

  /// Available loads, ascending, deduplicated.
  final List<double> loads;

  @override
  final String description;

  @override
  final bool isUnverifiedAssumption;

  static List<double> _normalize(Iterable<double> loadsLb) {
    final sorted = loadsLb.toSet().toList()..sort();
    if (sorted.isEmpty) {
      throw ArgumentError.value(
        loadsLb,
        'loadsLb',
        'A quantizer needs at least one available load',
      );
    }
    return List.unmodifiable(sorted);
  }

  @override
  double get minimumLoadLb => loads.first;

  @override
  double get maximumLoadLb => loads.last;

  @override
  double quantize(
    double desiredLb, {
    RoundingDirection direction = RoundingDirection.nearest,
  }) {
    if (desiredLb.isNaN) {
      throw ArgumentError.value(desiredLb, 'desiredLb', 'Must be a number');
    }
    if (desiredLb <= minimumLoadLb) {
      return minimumLoadLb;
    }
    if (desiredLb >= maximumLoadLb) {
      return maximumLoadLb;
    }
    for (final load in loads) {
      if ((load - desiredLb).abs() <= _tolerance) {
        return load;
      }
    }
    final below = loads.lastWhere((load) => load < desiredLb);
    final above = loads.firstWhere((load) => load > desiredLb);
    return switch (direction) {
      RoundingDirection.down => below,
      RoundingDirection.up => above,
      // Ties break down: a weight the lifter has not earned is the worse error.
      RoundingDirection.nearest =>
        (desiredLb - below) <= (above - desiredLb) ? below : above,
    };
  }

  @override
  double stepUp(double fromLb) {
    for (final load in loads) {
      if (load > fromLb + _tolerance) {
        return load;
      }
    }
    return maximumLoadLb;
  }

  @override
  double stepDown(double fromLb) {
    double? best;
    for (final load in loads) {
      if (load < fromLb - _tolerance) {
        best = load;
      }
    }
    return best ?? minimumLoadLb;
  }

  @override
  String toString() =>
      'DiscreteLoadQuantizer($description, '
      '${loads.length} loads ${formatTrimmed(minimumLoadLb)}'
      '-${formatTrimmed(maximumLoadLb)} lb)';
}

/// The Pennington dumbbell rack: 5 to 125 lb in 5 lb steps, two of each.
///
/// From the written equipment list (2026-10-19), which replaced an earlier
/// from-memory 1-165 lb rack. Written out literally rather than generated so
/// it can be eyeballed against the floor.
const List<double> kPenningtonDumbbellRackLb = <double>[
  5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, //
  70, 75, 80, 85, 90, 95, 100, 105, 110, 115, 120, 125,
];

/// Dumbbell loads, **per dumbbell** - not the pair total.
///
/// A logged "40 lb dumbbell press" means 40 in each hand, which is how lifters
/// say it and how the rack is labelled. Volume math multiplies by hands at the
/// exercise level, not here.
final class DumbbellQuantizer extends DiscreteLoadQuantizer {
  DumbbellQuantizer({List<double> rackLb = kPenningtonDumbbellRackLb})
    : super(
        rackLb,
        description:
            'Pennington dumbbell rack (${formatTrimmed(rackLb.first)}'
            '-${formatTrimmed(rackLb.last)} lb, ${rackLb.length} pairs)',
        // From the written Pennington equipment list.
        isUnverifiedAssumption: false,
      );
}

/// **ASSUMPTION** - standard Olympic bar. Open question 3 in
/// `docs/rec-center-equipment.md`: nobody has confirmed the bars at Pennington
/// are 45 lb, or how many there are.
const double kAssumedBarbellWeightLb = 45;

/// **ASSUMPTION** - a conventional American plate set.
///
/// Open question 4 in `docs/rec-center-equipment.md`. This is the most
/// consequential unknown in this file: the smallest plate sets the smallest
/// possible barbell jump. With 2.5 lb plates the minimum increment is 5 lb; if
/// Pennington's lightest plate is 5 lb it is 10 lb, and every barbell
/// recommendation this engine makes shifts.
///
/// It is a parameter, not a constant buried in the math - pass the real set to
/// [BarbellQuantizer] the day it is counted.
const List<double> kAssumedPlateDenominationsLb = <double>[
  45,
  35,
  25,
  10,
  5,
  2.5,
];

/// Assumptions a screen should flag rather than present as measured fact.
const List<String> kLoadQuantizationAssumptions = <String>[
  'Barbell bar weight assumed 45 lb - unconfirmed (equipment doc, open question 3).',
  'Plate denominations assumed 45/35/25/10/5/2.5 lb - unconfirmed (open question 4). '
      'The smallest plate sets the smallest barbell jump.',
  'Selectorized stack spacing assumed 10 lb - no pin spacing has been recorded.',
  'Bench press and incline bench press are assumed plate-loaded; if Pennington '
      'runs selectorized benches, re-map them in LoadQuantizerRegistry.',
];

/// Bar weight plus **symmetric pairs** of plates.
///
/// Reachable loads are enumerated exactly (not greedily) from the plate set, so
/// the result is always a load that can genuinely be built: a 45 lb bar with the
/// default plates can be 45, 50, 55, 65, ... but never 47.5.
///
/// Both [barWeightLb] and [plateDenominationsLb] are injectable and both default
/// to **assumptions** - see [kAssumedBarbellWeightLb] and
/// [kAssumedPlateDenominationsLb]. [isUnverifiedAssumption] stays `true` until a
/// caller passes a verified set.
final class BarbellQuantizer extends DiscreteLoadQuantizer {
  factory BarbellQuantizer({
    double barWeightLb = kAssumedBarbellWeightLb,
    List<double> plateDenominationsLb = kAssumedPlateDenominationsLb,
    int maxPairsPerDenomination = 8,
    double maxLoadLb = 700,
    bool denominationsAreVerified = false,
  }) {
    if (barWeightLb < 0) {
      throw ArgumentError.value(
        barWeightLb,
        'barWeightLb',
        'Must not be negative',
      );
    }
    if (plateDenominationsLb.isEmpty) {
      throw ArgumentError.value(
        plateDenominationsLb,
        'plateDenominationsLb',
        'A barbell needs at least one plate denomination',
      );
    }
    if (maxLoadLb < barWeightLb) {
      throw ArgumentError.value(
        maxLoadLb,
        'maxLoadLb',
        'Cannot be lighter than the bar',
      );
    }
    final plates = plateDenominationsLb.toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final loads = _reachableLoads(
      barWeightLb: barWeightLb,
      platesLb: plates,
      maxPairs: maxPairsPerDenomination,
      maxLoadLb: maxLoadLb,
    );
    final plateLabel = plates.map(formatTrimmed).join('/');
    return BarbellQuantizer._(
      loads,
      barWeightLb: barWeightLb,
      plateDenominationsLb: List.unmodifiable(plates),
      description: denominationsAreVerified
          ? 'Barbell: ${formatTrimmed(barWeightLb)} lb bar + $plateLabel lb plates'
          : 'Barbell: ${formatTrimmed(barWeightLb)} lb bar + $plateLabel lb plates '
                '(ASSUMED - plate denominations unconfirmed)',
      isUnverifiedAssumption: !denominationsAreVerified,
    );
  }

  BarbellQuantizer._(
    super.loadsLb, {
    required this.barWeightLb,
    required this.plateDenominationsLb,
    required super.description,
    required super.isUnverifiedAssumption,
  });

  final double barWeightLb;

  /// Plate denominations in use, heaviest first.
  final List<double> plateDenominationsLb;

  /// The smallest increase this bar can express: twice the lightest plate.
  double get smallestIncrementLb => plateDenominationsLb.last * 2;

  /// Plates to hang on **each side** for [totalLb], heaviest first, or `null`
  /// when [totalLb] cannot be built from this plate set.
  ///
  /// Greedy, which is exact for conventional descending plate sets. Always feed
  /// it a [quantize]d load.
  Map<double, int>? platesPerSide(double totalLb) {
    var remainingPerSide = (totalLb - barWeightLb) / 2;
    if (remainingPerSide < -_tolerance) {
      return null;
    }
    final result = <double, int>{};
    for (final plate in plateDenominationsLb) {
      final count = (remainingPerSide + _tolerance) ~/ plate;
      if (count > 0) {
        result[plate] = count;
        remainingPerSide -= count * plate;
      }
    }
    return remainingPerSide.abs() <= _tolerance ? result : null;
  }

  /// Enumerates every total that bar + symmetric plate pairs can build.
  ///
  /// Works in integer quarter-pounds so 2.5 lb plates never accumulate floating
  /// point drift across eight pairs.
  static List<double> _reachableLoads({
    required double barWeightLb,
    required List<double> platesLb,
    required int maxPairs,
    required double maxLoadLb,
  }) {
    final maxPerSideQuarters = ((maxLoadLb - barWeightLb) / 2 * 4).floor();
    var sums = <int>{0};
    for (final plate in platesLb) {
      final step = (plate * 4).round();
      if (step <= 0) {
        continue;
      }
      final next = <int>{};
      for (final sum in sums) {
        var accumulated = sum;
        for (var pairs = 0; pairs <= maxPairs; pairs++) {
          if (accumulated > maxPerSideQuarters) {
            break;
          }
          next.add(accumulated);
          accumulated += step;
        }
      }
      sums = next;
    }
    return sums.map((quarters) => barWeightLb + quarters / 2).toList();
  }
}

/// **ASSUMPTION** - selectorized stack pin spacing, in pounds.
const double kAssumedStackIncrementLb = 10;

/// A selectorized weight stack (cable column, lat pulldown, leg extension...).
///
/// Pin spacing at Pennington has never been recorded, so [incrementLb] defaults
/// to an assumption and the quantizer reports itself as unverified. Machines
/// commonly differ from each other, so the registry is the place to give one
/// machine its own spacing once it is measured.
final class MachineStackQuantizer extends DiscreteLoadQuantizer {
  factory MachineStackQuantizer({
    double incrementLb = kAssumedStackIncrementLb,
    double minimumLb = kAssumedStackIncrementLb,
    double maximumLb = 250,
    String machineName = 'Selectorized stack',
    bool spacingIsVerified = false,
  }) {
    if (incrementLb <= 0) {
      throw ArgumentError.value(incrementLb, 'incrementLb', 'Must be positive');
    }
    if (maximumLb < minimumLb) {
      throw ArgumentError.value(
        maximumLb,
        'maximumLb',
        'Cannot be lighter than the minimum',
      );
    }
    final loads = <double>[];
    for (
      var load = minimumLb;
      load <= maximumLb + _tolerance;
      load += incrementLb
    ) {
      loads.add(load);
    }
    return MachineStackQuantizer._(
      loads,
      incrementLb: incrementLb,
      description: spacingIsVerified
          ? '$machineName (${formatTrimmed(incrementLb)} lb plates)'
          : '$machineName (${formatTrimmed(incrementLb)} lb plates ASSUMED - '
                'pin spacing not yet measured)',
      isUnverifiedAssumption: !spacingIsVerified,
    );
  }

  MachineStackQuantizer._(
    super.loadsLb, {
    required this.incrementLb,
    required super.description,
    required super.isUnverifiedAssumption,
  });

  final double incrementLb;
}

/// Exercises with no external load: push-ups, pull-ups, runs, hikes.
///
/// Nothing to snap to, so the desired value passes through unchanged. Progress
/// bodyweight work with **reps**, not load; if the lifter adds a dumbbell
/// between their feet, quantize that added load with [DumbbellQuantizer].
final class BodyweightQuantizer implements LoadQuantizer {
  const BodyweightQuantizer();

  @override
  String get description =>
      'Bodyweight / outdoor - no external load to snap to';

  @override
  bool get isUnverifiedAssumption => false;

  @override
  double get minimumLoadLb => 0;

  @override
  double get maximumLoadLb => double.infinity;

  @override
  double quantize(
    double desiredLb, {
    RoundingDirection direction = RoundingDirection.nearest,
  }) => desiredLb.isNaN || desiredLb < 0 ? 0 : desiredLb;

  @override
  double stepUp(double fromLb) => fromLb;

  @override
  double stepDown(double fromLb) => fromLb;
}

/// Which quantizer applies to which equipment.
///
/// Pluggable by design: pass [overrides] to give one machine measured spacing,
/// or to swap bench press to a selectorized quantizer, without touching the
/// progression engine.
final class LoadQuantizerRegistry {
  LoadQuantizerRegistry({
    Map<EquipmentType, LoadQuantizer> overrides = const {},
    LoadQuantizer? fallback,
  }) : _overrides = Map.unmodifiable(overrides),
       _fallback = fallback ?? const BodyweightQuantizer();

  /// The Rec Center as currently understood, assumptions and all.
  factory LoadQuantizerRegistry.pennington({
    Map<EquipmentType, LoadQuantizer> overrides = const {},
  }) => LoadQuantizerRegistry(overrides: overrides);

  final Map<EquipmentType, LoadQuantizer> _overrides;
  final LoadQuantizer _fallback;

  static final DumbbellQuantizer _dumbbells = DumbbellQuantizer();
  static final BarbellQuantizer _barbell = BarbellQuantizer();
  static final MachineStackQuantizer _stack = MachineStackQuantizer();
  static const BodyweightQuantizer _bodyweight = BodyweightQuantizer();

  /// The quantizer for [equipment]; overrides win.
  LoadQuantizer forEquipment(EquipmentType equipment) {
    final override = _overrides[equipment];
    if (override != null) {
      return override;
    }
    return switch (equipment) {
      EquipmentType.dumbbell => _dumbbells,
      // Squat racks and benches are assumed plate-loaded barbell stations.
      EquipmentType.barbell ||
      EquipmentType.squatRack ||
      EquipmentType.benchPress ||
      EquipmentType.inclineBenchPress => _barbell,
      // Everything cable- or pin-driven shares the assumed stack spacing until
      // somebody measures each machine.
      EquipmentType.cableStation ||
      EquipmentType.latPulldown ||
      EquipmentType.legExtension ||
      EquipmentType.hamstringCurl ||
      EquipmentType.cableRow ||
      EquipmentType.backRow ||
      EquipmentType.pecDeck ||
      EquipmentType.rearDeltFly ||
      EquipmentType.tricepPushdown => _stack,
      EquipmentType.bodyweight || EquipmentType.outdoor => _bodyweight,
    };
  }

  /// `true` when any equipment in use is still running on assumed numbers -
  /// worth a one-line disclaimer in the UI.
  bool get hasUnverifiedAssumptions => EquipmentType.values
      .map(forEquipment)
      .any((quantizer) => quantizer.isUnverifiedAssumption);

  /// Convenience: snap [desiredLb] for [equipment].
  double quantize(
    double desiredLb,
    EquipmentType equipment, {
    RoundingDirection direction = RoundingDirection.nearest,
  }) => forEquipment(equipment).quantize(desiredLb, direction: direction);

  /// The fallback used for equipment with no rule - bodyweight passthrough.
  LoadQuantizer get fallback => _fallback;
}
