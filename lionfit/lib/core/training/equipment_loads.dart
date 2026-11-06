/// Load tables built from the **real** Pennington equipment list.
///
/// Every `rec_center_equipment` row with a weight range carries four numbers
/// copied from `assets/Pennington Rec Center Equipment List.docx`: kind, min,
/// max and step (migration 0008). This file turns one of those rows into a
/// [LoadQuantizer], so a suggested load always lands on a weight that machine
/// can actually be set to - 12.5 lb steps on the leg extension, 20 lb on the
/// leg press, 5 lb on the dumbbells.
///
/// The three kinds, because the document's "increment" column means different
/// things for different gear:
///
/// | Kind | Reachable totals |
/// | --- | --- |
/// | [LoadKind.stack] | `min + k * step` - a pin stack |
/// | [LoadKind.fixedSet] | `min + k * step`, plus `max` - separate dumbbells, bars, bells |
/// | [LoadKind.plates] | `min + k * 2 * step` - `step` is the smallest plate and plates go on both sides |
///
/// Pure Dart.
library;

import 'load_quantization.dart';
import 'models.dart';

enum LoadKind {
  stack('stack'),
  plates('plates'),
  fixedSet('fixed_set');

  const LoadKind(this.wireName);

  final String wireName;

  static LoadKind? tryFromWireName(String? wireName) {
    for (final kind in values) {
      if (kind.wireName == wireName) return kind;
    }
    return null;
  }
}

/// The load columns of one equipment row, in the unit the row is labelled in.
final class EquipmentLoadSpec {
  const EquipmentLoadSpec({
    required this.kind,
    required this.min,
    required this.max,
    required this.step,
    this.unit = WeightUnit.lb,
    this.explicitLoadsLb,
  });

  final LoadKind kind;
  final double min;
  final double max;
  final double step;

  /// Kettlebells are labelled in kg; everything else on the list is in lb.
  final WeightUnit unit;

  /// `load_increments_lb` when the row lists its denominations outright (the
  /// dumbbell rack). Wins over the computed range.
  final List<double>? explicitLoadsLb;

  /// The smallest change in total load this equipment can make, in lb.
  double get smallestJumpLb =>
      unit.toLb(kind == LoadKind.plates ? step * 2 : step);

  /// Every load this equipment can be set to, in pounds, ascending.
  List<double> loadsLb() {
    final explicit = explicitLoadsLb;
    if (explicit != null && explicit.isNotEmpty) {
      return (explicit.toSet().toList()..sort());
    }
    final jump = kind == LoadKind.plates ? step * 2 : step;
    final loads = <double>[];
    // Integer steps, not repeated addition: 12.5 added 15 times drifts.
    final count = ((max - min) / jump + 1e-9).floor();
    for (var i = 0; i <= count; i++) {
      loads.add(_roundLb(unit.toLb(min + i * jump)));
    }
    // A fixed set includes its heaviest implement even when the step does
    // not land on it (kettlebells: 3 + 2k never reaches 24).
    final maxLb = _roundLb(unit.toLb(max));
    if (kind == LoadKind.fixedSet && (loads.last - maxLb).abs() > 1e-6) {
      loads.add(maxLb);
    }
    return loads;
  }

  LoadQuantizer toQuantizer({required String label}) => DiscreteLoadQuantizer(
    loadsLb(),
    description:
        '$label (${formatTrimmed(min)}-${formatTrimmed(max)} ${unit.wireName})',
  );

  static double _roundLb(double value) => (value * 100).round() / 100;
}
