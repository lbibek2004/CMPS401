/// One row of `rec_center_equipment`.
///
/// Parsed defensively: the load columns arrive in migration 0008, and a
/// database that has not had it applied yet must still produce a usable item
/// (no load spec) rather than a crash.
library;

import '../../../core/training/equipment_loads.dart';
import '../../../core/training/load_quantization.dart';
import '../../../core/training/models.dart';

enum EquipmentStatus {
  available('available'),
  occupied('occupied'),
  outOfService('out_of_service'),
  unknown('unknown');

  const EquipmentStatus(this.wireName);

  final String wireName;

  static EquipmentStatus fromWire(String? wire) => values.firstWhere(
    (status) => status.wireName == wire,
    orElse: () => EquipmentStatus.unknown,
  );
}

final class EquipmentItem {
  const EquipmentItem({
    required this.slug,
    required this.label,
    this.quantity,
    this.status = EquipmentStatus.available,
    this.isInventoryItem = true,
    this.loadSpec,
    this.notes,
    this.isVerified = false,
  });

  factory EquipmentItem.fromRow(Map<String, dynamic> row) {
    final kind = LoadKind.tryFromWireName(row['load_kind'] as String?);
    final min = (row['load_min'] as num?)?.toDouble();
    final max = (row['load_max'] as num?)?.toDouble();
    final step = (row['load_step'] as num?)?.toDouble();
    final explicit = [
      for (final value in (row['load_increments_lb'] as List?) ?? const [])
        (value as num).toDouble(),
    ];
    return EquipmentItem(
      slug: row['equipment_type'] as String,
      label: row['label'] as String,
      quantity: (row['quantity'] as num?)?.toInt(),
      status: EquipmentStatus.fromWire(row['availability_status'] as String?),
      isInventoryItem: (row['is_inventory_item'] as bool?) ?? true,
      loadSpec: kind == null || min == null || max == null || step == null
          ? null
          : EquipmentLoadSpec(
              kind: kind,
              min: min,
              max: max,
              step: step,
              unit: (row['load_unit'] as String?) == 'kg'
                  ? WeightUnit.kg
                  : WeightUnit.lb,
              explicitLoadsLb: explicit.isEmpty ? null : explicit,
            ),
      notes: row['notes'] as String?,
      isVerified: (row['is_verified'] as bool?) ?? false,
    );
  }

  final String slug;
  final String label;

  /// Null = known to exist, count unknown. Zero = not on the floor.
  final int? quantity;
  final EquipmentStatus status;
  final bool isInventoryItem;

  /// Null for equipment with nothing to load (cardio, benches) and for rows
  /// from before migration 0008.
  final EquipmentLoadSpec? loadSpec;
  final String? notes;

  /// Someone has checked this row against the floor.
  final bool isVerified;

  /// Usable right now: listed as available and not counted as zero.
  bool get isUsable => status == EquipmentStatus.available && quantity != 0;

  LoadQuantizer? get quantizer => loadSpec?.toQuantizer(label: label);
}

/// The equipment list, indexed by slug, with the two questions every caller
/// asks of it.
final class EquipmentInventory {
  EquipmentInventory(Iterable<EquipmentItem> items)
    : _bySlug = {for (final item in items) item.slug: item};

  final Map<String, EquipmentItem> _bySlug;

  EquipmentItem? operator [](String slug) => _bySlug[slug];

  Iterable<EquipmentItem> get items => _bySlug.values;

  bool get isEmpty => _bySlug.isEmpty;

  /// True when every piece in [slugs] is usable. The two non-gym sentinels
  /// (`bodyweight`, `outdoor`) are always usable even when the row is missing.
  ///
  /// An empty inventory means "not loaded", and answers true: hiding the whole
  /// catalog because one request failed would be worse than showing it.
  bool allUsable(Iterable<String> slugs) {
    if (isEmpty) return true;
    for (final slug in slugs) {
      if (slug == 'bodyweight' || slug == 'outdoor') continue;
      final item = _bySlug[slug];
      if (item == null || !item.isUsable) return false;
    }
    return true;
  }

  /// The first piece in [slugs] with a load table - the one a suggested load
  /// should be rounded to. Dumbbells on a bench round to the dumbbells.
  EquipmentItem? loadBearing(Iterable<String> slugs) {
    for (final slug in slugs) {
      final item = _bySlug[slug];
      if (item?.loadSpec != null) return item;
    }
    return null;
  }

  String labelOf(String slug) => _bySlug[slug]?.label ?? slug;
}
