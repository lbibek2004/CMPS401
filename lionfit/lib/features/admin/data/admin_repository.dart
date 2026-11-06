import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/equipment_item.dart';
import '../domain/admin_models.dart';

/// A failed admin write, in words an admin can act on.
final class AdminWriteFailure implements Exception {
  const AdminWriteFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Writes to the two shared reference tables. **Only the database decides
/// who may do this**: every call runs as the signed-in user, and the RLS
/// policies from migration 0003 allow it only when `is_admin()` is true. A
/// member who reached this code would get "permission denied", not a write.
///
/// Nothing here touches another user's rows - admin is content management,
/// not a view into anyone's training data.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<void> updateEquipment(
    String slug, {
    required EquipmentStatus status,
    required int? quantity,
    required bool isVerified,
    required String label,
    String? notes,
  }) => _guard(
    () => _client
        .from('rec_center_equipment')
        .update({
          'label': label.trim(),
          'availability_status': status.wireName,
          'quantity': quantity,
          'is_verified': isVerified,
          'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
        })
        .eq('equipment_type', slug)
        .select('equipment_type')
        .single(),
  );

  Future<void> addEquipment({
    required String slug,
    required String label,
    required EquipmentStatus status,
    required int? quantity,
    required bool isVerified,
    String? notes,
  }) => _guard(
    () => _client.from('rec_center_equipment').insert({
      'equipment_type': slug,
      'label': label.trim(),
      'availability_status': status.wireName,
      'quantity': quantity,
      'is_verified': isVerified,
      'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
    }),
  );

  Future<void> updateExercise(String id, ExerciseDraft draft) => _guard(
    () => _client
        .from('exercises')
        .update(draft.toRow())
        .eq('id', id)
        .select('id')
        .single(),
  );

  Future<void> setExerciseActive(String id, bool active) => _guard(
    () => _client
        .from('exercises')
        .update({'is_active': active})
        .eq('id', id)
        .select('id')
        .single(),
  );

  Future<void> addExercise(ExerciseDraft draft) => _guard(
    () => _client.from('exercises').insert(draft.toRow(includeSlug: true)),
  );

  /// `.select().single()` after an update matters: under RLS a refused
  /// UPDATE is not an error, it just matches zero rows. Asking for the row
  /// back turns "silently nothing" into a failure the admin sees.
  static Future<void> _guard(Future<Object?> Function() write) async {
    try {
      await write();
    } on PostgrestException catch (error) {
      throw AdminWriteFailure(switch (error.code) {
        '42501' ||
        'PGRST116' => 'Not saved: this account is not an admin on the server.',
        '23505' => 'Not saved: that ID is already taken. Pick another.',
        '23514' => 'Not saved: a value is out of range or badly formatted.',
        _ => 'Not saved: ${error.message}',
      });
    } catch (_) {
      throw const AdminWriteFailure(
        'Not saved: check your connection and try again.',
      );
    }
  }
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(supabaseClientProvider)),
);

/// After an admin write: refresh everything built from the reference data,
/// so the change shows up in the plan, the picker and the map at once.
void refreshReferenceData(WidgetRef ref) {
  ref.invalidate(exerciseCatalogProvider);
  ref.invalidate(equipmentProvider);
}
