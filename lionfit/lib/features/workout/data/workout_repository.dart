import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/training/models.dart';
import '../domain/workout_models.dart';

/// Every Supabase call the logger and the muscle map make.
///
/// All of it runs as the signed-in user under RLS: the catalog is readable by
/// any member, and sessions / sets are scoped to `auth.uid()` by policy, so
/// none of these queries filter by user themselves except where a row needs
/// an owner on insert.
///
/// Not offline-safe yet. A dropped connection surfaces as an error the screen
/// shows; the queued-write layer (`offline-sync-engineer`) is still to come.
/// The `client_uuid` column it will rely on already exists.
class WorkoutRepository {
  WorkoutRepository(this._client);

  final SupabaseClient _client;

  static const _setColumns =
      'id, workout_id, exercise_id, set_index, set_type, weight, unit, reps, '
      'rpe, rir, performed_on, performed_at';

  Future<List<CatalogExercise>> fetchCatalog() async {
    final rows = await _client
        .from('exercises')
        .select(
          'id, slug, name, primary_muscle_groups, secondary_muscle_groups, '
          'unmapped_muscle_groups, required_equipment, movement_pattern, '
          'is_outdoor, notes',
        )
        .eq('is_active', true)
        .order('name');
    return rows.map(CatalogExercise.fromRow).toList(growable: false);
  }

  /// `equipment_type` -> human label, for the picker's subtitles.
  Future<Map<String, String>> fetchEquipmentLabels() async {
    final rows = await _client
        .from('rec_center_equipment')
        .select('equipment_type, label');
    return {
      for (final row in rows)
        row['equipment_type'] as String: row['label'] as String,
    };
  }

  /// The most recent session scheduled for [day], or null.
  Future<String?> findWorkoutOn(DateTime day) async {
    final row = await _client
        .from('user_workouts')
        .select('id')
        .eq('scheduled_date', isoDate(day))
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row?['id'] as String?;
  }

  Future<String> createWorkout(DateTime day) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sign in before logging a workout.');
    }
    final row = await _client
        .from('user_workouts')
        .insert({
          // Required by the insert policy (user_id = auth.uid()).
          'user_id': userId,
          'scheduled_date': isoDate(day),
          'title': 'Workout',
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<List<SetRecord>> setsForWorkout(String workoutId) async {
    final rows = await _client
        .from('workout_logs')
        .select(_setColumns)
        .eq('workout_id', workoutId)
        .order('performed_at');
    return rows.map(SetRecord.fromRow).toList(growable: false);
  }

  /// Every set on or after [from], for the muscle map.
  Future<List<SetRecord>> setsSince(DateTime from) async {
    final rows = await _client
        .from('workout_logs')
        .select(_setColumns)
        .gte('performed_on', isoDate(from))
        .order('performed_on');
    return rows.map(SetRecord.fromRow).toList(growable: false);
  }

  Future<SetRecord> logSet({
    required String workoutId,
    required int setIndex,
    required NewSet set,
  }) async {
    final row = await _client
        .from('workout_logs')
        .insert({
          'workout_id': workoutId,
          // Overwritten by the inherit-parent trigger; sent because the
          // column is NOT NULL and the composite FK names it.
          'user_id': _client.auth.currentUser?.id,
          'exercise_id': set.exerciseId,
          'set_index': setIndex,
          'set_type': set.setType.wireName,
          'weight': set.weight,
          'unit': set.unit.wireName,
          'reps': set.reps,
          'rpe': set.rpe,
          'rir': set.rir,
        })
        .select(_setColumns)
        .single();
    return SetRecord.fromRow(row);
  }

  Future<void> deleteSet(String setId) =>
      _client.from('workout_logs').delete().eq('id', setId);
}

final workoutRepositoryProvider = Provider<WorkoutRepository>(
  (ref) => WorkoutRepository(ref.watch(supabaseClientProvider)),
);

final exerciseCatalogProvider = FutureProvider<List<CatalogExercise>>(
  (ref) => ref.watch(workoutRepositoryProvider).fetchCatalog(),
);

final equipmentLabelsProvider = FutureProvider<Map<String, String>>(
  (ref) => ref.watch(workoutRepositoryProvider).fetchEquipmentLabels(),
);

/// The last 30 days of sets - the longest window the muscle map offers.
final recentSetsProvider = FutureProvider<List<SetRecord>>((ref) {
  final today = calendarDay(DateTime.now());
  return ref
      .watch(workoutRepositoryProvider)
      .setsSince(today.subtract(const Duration(days: 29)));
});

/// Today's session as the logger sees it.
final class TodaySession {
  const TodaySession({
    required this.day,
    this.workoutId,
    this.sets = const [],
    this.exerciseOrder = const [],
  });

  final DateTime day;

  /// Null until the first set is logged - an empty session is never written.
  final String? workoutId;
  final List<SetRecord> sets;

  /// Exercises on screen, in the order they were added.
  final List<String> exerciseOrder;

  List<SetRecord> setsFor(String exerciseId) =>
      sets.where((set) => set.exerciseId == exerciseId).toList()
        ..sort((a, b) => a.setIndex.compareTo(b.setIndex));

  TodaySession copyWith({
    String? workoutId,
    List<SetRecord>? sets,
    List<String>? exerciseOrder,
  }) => TodaySession(
    day: day,
    workoutId: workoutId ?? this.workoutId,
    sets: sets ?? this.sets,
    exerciseOrder: exerciseOrder ?? this.exerciseOrder,
  );
}

class TodaySessionController extends AsyncNotifier<TodaySession> {
  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);

  @override
  Future<TodaySession> build() async {
    final day = calendarDay(DateTime.now());
    final repo = ref.watch(workoutRepositoryProvider);
    final workoutId = await repo.findWorkoutOn(day);
    if (workoutId == null) return TodaySession(day: day);
    final sets = await repo.setsForWorkout(workoutId);
    final order = <String>[];
    for (final set in sets) {
      if (!order.contains(set.exerciseId)) order.add(set.exerciseId);
    }
    return TodaySession(
      day: day,
      workoutId: workoutId,
      sets: sets,
      exerciseOrder: order,
    );
  }

  void addExercise(String exerciseId) {
    final current = state.value;
    if (current == null || current.exerciseOrder.contains(exerciseId)) return;
    state = AsyncData(
      current.copyWith(exerciseOrder: [...current.exerciseOrder, exerciseId]),
    );
  }

  /// Removes an exercise card that has no sets yet.
  void removeExercise(String exerciseId) {
    final current = state.value;
    if (current == null || current.setsFor(exerciseId).isNotEmpty) return;
    state = AsyncData(
      current.copyWith(
        exerciseOrder: [
          for (final id in current.exerciseOrder)
            if (id != exerciseId) id,
        ],
      ),
    );
  }

  /// Saves one set. Throws on failure so the form can keep the user's input
  /// and show the error.
  Future<void> logSet(NewSet set) async {
    final current = state.requireValue;
    final workoutId =
        current.workoutId ?? await _repo.createWorkout(current.day);
    final existing = current.setsFor(set.exerciseId);
    final nextIndex = existing.isEmpty ? 1 : existing.last.setIndex + 1;
    final saved = await _repo.logSet(
      workoutId: workoutId,
      setIndex: nextIndex,
      set: set,
    );
    final latest = state.value ?? current;
    state = AsyncData(
      latest.copyWith(
        workoutId: workoutId,
        sets: [...latest.sets, saved],
        exerciseOrder: latest.exerciseOrder.contains(set.exerciseId)
            ? latest.exerciseOrder
            : [...latest.exerciseOrder, set.exerciseId],
      ),
    );
    ref.invalidate(recentSetsProvider);
  }

  Future<void> deleteSet(String setId) async {
    await _repo.deleteSet(setId);
    final latest = state.requireValue;
    state = AsyncData(
      latest.copyWith(
        sets: [
          for (final set in latest.sets)
            if (set.id != setId) set,
        ],
      ),
    );
    ref.invalidate(recentSetsProvider);
  }
}

final todaySessionProvider =
    AsyncNotifierProvider<TodaySessionController, TodaySession>(
      TodaySessionController.new,
    );

/// Formats a set for the log list: "135 lb × 10 · RPE 8".
String describeSet(SetRecord set) {
  final load = set.weight == null || set.weight == 0
      ? 'Bodyweight'
      : '${formatTrimmed(set.weight!)} ${set.unit.wireName}';
  final reps = set.reps == null ? '' : ' × ${set.reps}';
  final effort = set.rpe != null
      ? ' · RPE ${formatTrimmed(set.rpe!)}'
      : set.rir != null
      ? ' · ${set.rir} RIR'
      : '';
  return '$load$reps$effort';
}
