import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/training/models.dart';
import '../application/rest_timer_controller.dart';
import '../domain/equipment_item.dart';
import '../domain/training_profile.dart';
import '../domain/workout_models.dart';

/// The server accepted a profile write but the row did not change - no
/// profile row for this account, or RLS refused it without an error.
final class ProfileNotSaved implements Exception {
  const ProfileNotSaved();

  @override
  String toString() => 'The profile row was not updated.';
}

/// Every Supabase call the logger, the coach and the muscle map make.
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

  /// The whole catalog, retired rows included: an old set still needs its
  /// exercise's name and muscle mapping. Screens that *offer* exercises filter
  /// on [CatalogExercise.isActive].
  Future<List<CatalogExercise>> fetchCatalog() async {
    final rows = await _client
        .from('exercises')
        .select(
          'id, slug, name, primary_muscle_groups, secondary_muscle_groups, '
          'unmapped_muscle_groups, required_equipment, movement_pattern, '
          'is_outdoor, is_active, notes',
        )
        .order('name');
    return rows.map(CatalogExercise.fromRow).toList(growable: false);
  }

  /// Every equipment row. `select()` (all columns) rather than a list so the
  /// app keeps working against a database that has not had migration 0008's
  /// load columns applied yet - [EquipmentItem.fromRow] treats them as
  /// optional.
  Future<List<EquipmentItem>> fetchEquipment() async {
    final rows = await _client.from('rec_center_equipment').select();
    return rows.map(EquipmentItem.fromRow).toList(growable: false);
  }

  /// The signed-in user's profile row, or the column defaults.
  ///
  /// `select()` (all columns), not a list: the app has to keep working
  /// against a database without migration 0009, and [TrainingProfile.fromRow]
  /// reads the missing columns as "feature off".
  Future<TrainingProfile> fetchProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const TrainingProfile();
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? const TrainingProfile() : TrainingProfile.fromRow(row);
  }

  /// Writes the granted columns only - see [TrainingProfile.toRow].
  ///
  /// Asks for the row back: under RLS an UPDATE that matches nothing is not
  /// an error, it is "0 rows" - and a silent no-op here would leave the
  /// survey owed forever. [ProfileNotSaved] makes that visible.
  Future<void> updateProfile(TrainingProfile profile) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in first.');
    final updated = await _client
        .from('profiles')
        .update(profile.toRow())
        .eq('id', userId)
        .select('id');
    if (updated.isEmpty) throw const ProfileNotSaved();
  }

  /// Survey answers. Empty when there are none, or when migration 0009 is not
  /// applied yet - the coach then falls back to bodyweight estimates.
  Future<List<StrengthBaseline>> fetchBaselines() async {
    try {
      final rows = await _client
          .from('user_strength_baselines')
          .select('exercise_id, weight, unit, reps, updated_at');
      return rows.map(StrengthBaseline.fromRow).toList(growable: false);
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) return const [];
      rethrow;
    }
  }

  /// Replaces the user's survey answers with [baselines].
  Future<void> replaceBaselines(List<StrengthBaseline> baselines) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in first.');
    // A no-op on a database without migration 0009 (a survey retake there
    // still saves the profile answers).
    try {
      await _client
          .from('user_strength_baselines')
          .delete()
          .eq('user_id', userId);
      if (baselines.isEmpty) return;
      await _client.from('user_strength_baselines').insert([
        for (final b in baselines) b.toRow(userId),
      ]);
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) return;
      rethrow;
    }
  }

  /// Swaps on the plan between [from] and [to], inclusive.
  Future<List<PlanSwap>> fetchSwaps(DateTime from, DateTime to) async {
    try {
      final rows = await _client
          .from('user_plan_swaps')
          .select('plan_date, original_exercise_id, replacement_exercise_id')
          .gte('plan_date', isoDate(from))
          .lte('plan_date', isoDate(to));
      return rows.map(PlanSwap.fromRow).toList(growable: false);
    } on PostgrestException catch (error) {
      if (_isMissingRelation(error)) return const [];
      rethrow;
    }
  }

  /// Upserts on (user, day, original): swapping a slot twice keeps one row.
  Future<void> saveSwap(PlanSwap swap) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in first.');
    await _client.from('user_plan_swaps').upsert({
      'user_id': userId,
      'plan_date': isoDate(swap.planDate),
      'original_exercise_id': swap.originalExerciseId,
      'replacement_exercise_id': swap.replacementExerciseId,
    }, onConflict: 'user_id,plan_date,original_exercise_id');
  }

  Future<void> deleteSwap(DateTime planDate, String originalExerciseId) =>
      _client
          .from('user_plan_swaps')
          .delete()
          .eq('plan_date', isoDate(planDate))
          .eq('original_exercise_id', originalExerciseId);

  /// "relation does not exist" from Postgres, or PostgREST's "table not in
  /// the schema cache" - both mean migration 0009 has not been applied.
  static bool _isMissingRelation(PostgrestException error) =>
      error.code == '42P01' || error.code == 'PGRST205';

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

  /// Every set on or after [from]. RLS returns only the caller's rows, and
  /// `idx_workout_logs_user_performed_on` serves the range.
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

  /// Rewrites the editable fields of one set. Owner and day are not editable
  /// here - the inherit-parent trigger owns both.
  Future<SetRecord> updateSet(String setId, NewSet set) async {
    final row = await _client
        .from('workout_logs')
        .update({
          'set_type': set.setType.wireName,
          'weight': set.weight,
          'unit': set.unit.wireName,
          'reps': set.reps,
          'rpe': set.rpe,
          'rir': set.rir,
        })
        .eq('id', setId)
        .select(_setColumns)
        .single();
    return SetRecord.fromRow(row);
  }

  Future<void> deleteSet(String setId) =>
      _client.from('workout_logs').delete().eq('id', setId);
}

/// Rebuilt when the signed-in user changes, and with it every provider that
/// reads through it. Without this, signing out and in as someone else would
/// keep showing the first account's cached plan and history.
final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  ref.watch(sessionProvider.select((session) => session?.user.id));
  return WorkoutRepository(ref.watch(supabaseClientProvider));
});

/// Every exercise, retired included. Use [activeCatalogProvider] to offer.
final exerciseCatalogProvider = FutureProvider<List<CatalogExercise>>(
  (ref) => ref.watch(workoutRepositoryProvider).fetchCatalog(),
);

final equipmentProvider = FutureProvider<List<EquipmentItem>>(
  (ref) => ref.watch(workoutRepositoryProvider).fetchEquipment(),
);

/// Equipment as the engine reads it. A failed request yields an empty
/// inventory, which means "assume available" - see
/// [EquipmentInventory.allUsable]. Hiding every exercise because one request
/// failed would be worse.
final inventoryProvider = FutureProvider<EquipmentInventory>((ref) async {
  try {
    return EquipmentInventory(await ref.watch(equipmentProvider.future));
  } catch (_) {
    return EquipmentInventory(const []);
  }
});

/// Active exercises whose equipment is on the floor - what the picker offers.
final activeCatalogProvider = FutureProvider<List<CatalogExercise>>((
  ref,
) async {
  final all = await ref.watch(exerciseCatalogProvider.future);
  final inventory = await ref.watch(inventoryProvider.future);
  return [
    for (final exercise in all)
      if (exercise.isActive && inventory.allUsable(exercise.requiredEquipment))
        exercise,
  ];
});

/// `equipment_type` -> human label, for the picker's subtitles.
final equipmentLabelsProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  final inventory = await ref.watch(inventoryProvider.future);
  return {for (final item in inventory.items) item.slug: item.label};
});

final trainingProfileProvider = FutureProvider<TrainingProfile>((ref) async {
  try {
    return await ref.watch(workoutRepositoryProvider).fetchProfile();
  } catch (_) {
    return const TrainingProfile();
  }
});

/// The survey's "what can you lift now?" answers. Never an error: without
/// them the coach estimates from experience and bodyweight.
final strengthBaselinesProvider = FutureProvider<List<StrengthBaseline>>((
  ref,
) async {
  try {
    return await ref.watch(workoutRepositoryProvider).fetchBaselines();
  } catch (_) {
    return const [];
  }
});

/// How far back the coach, the progress chart and the history screen read.
/// Twelve weeks: enough for a trend, small enough to be one request (a few
/// hundred rows for a consistent lifter).
const int kHistoryDays = 84;

/// The user's last [kHistoryDays] days of sets.
///
/// **This is the query that feeds the recommendation engine.** RLS scopes it
/// to the signed-in user; `CoachEngine` turns it into next loads and muscle
/// gaps (see `lib/features/coach/domain/coach_engine.dart`).
final trainingHistoryProvider = FutureProvider<List<SetRecord>>((ref) {
  final today = calendarDay(DateTime.now());
  return ref
      .watch(workoutRepositoryProvider)
      .setsSince(today.subtract(const Duration(days: kHistoryDays - 1)));
});

/// The last 30 days of sets - the longest window the muscle map offers.
/// Derived from [trainingHistoryProvider], so it costs no extra request.
final recentSetsProvider = FutureProvider<List<SetRecord>>((ref) async {
  final since = calendarDay(DateTime.now()).subtract(const Duration(days: 29));
  final all = await ref.watch(trainingHistoryProvider.future);
  return [
    for (final set in all)
      if (!set.performedOn.isBefore(since)) set,
  ];
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

  /// Saves **one** set and starts the rest timer. Throws on failure so the
  /// form can keep the user's input and show the error.
  ///
  /// There is deliberately no "log several sets" call: every set is its own
  /// save with its own effort rating, and every save starts a rest.
  Future<void> logSet(NewSet set) async {
    // The session has to be loaded before the first write can number sets.
    final current = state.value ?? await future;
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
    ref.invalidate(trainingHistoryProvider);
    _startRest(set.exerciseId);
  }

  /// Rest starts the moment a set is saved - from any screen. Cardio has no
  /// sets to rest between.
  void _startRest(String exerciseId) {
    final catalog = ref.read(exerciseCatalogProvider).value ?? const [];
    for (final e in catalog) {
      if (e.id == exerciseId && e.isCardio) return;
    }
    final profile =
        ref.read(trainingProfileProvider).value ?? const TrainingProfile();
    ref
        .read(restTimerProvider.notifier)
        .start(Duration(seconds: profile.restTimerSeconds));
  }

  Future<void> updateSet(String setId, NewSet set) async {
    final saved = await _repo.updateSet(setId, set);
    final latest = state.requireValue;
    state = AsyncData(
      latest.copyWith(
        sets: [
          for (final existing in latest.sets)
            if (existing.id == setId) saved else existing,
        ],
      ),
    );
    ref.invalidate(trainingHistoryProvider);
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
    ref.invalidate(trainingHistoryProvider);
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
