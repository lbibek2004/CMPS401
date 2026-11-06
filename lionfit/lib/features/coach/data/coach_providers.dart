/// Riverpod wiring for the coach: Supabase rows in, [CoachEngine] decisions
/// out, and the optional AI phrasing on top.
///
/// The data path, end to end:
///
/// 1. [trainingHistoryProvider] - the user's last 12 weeks of `workout_logs`
///    (RLS: their rows only), plus the catalog, the equipment list and their
///    profile.
/// 2. [coachEngineProvider] - those four, handed to the pure-Dart engine.
/// 3. [coachBriefProvider] / [weeklyPlanProvider] - what the screens show.
///    Fully usable on their own.
/// 4. [coachInsightsProvider] - the brief sent to the `coach-insights` Edge
///    Function for Gemini phrasing. Null whenever that is unavailable, and the
///    screens fall back to the engine's own sentences.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/domain/workout_models.dart';
import '../domain/coach_engine.dart';
import '../domain/weekly_plan.dart';

final coachEngineProvider = FutureProvider<CoachEngine>((ref) async {
  final (catalog, inventory, history, profile, baselines) = await (
    ref.watch(exerciseCatalogProvider.future),
    ref.watch(inventoryProvider.future),
    ref.watch(trainingHistoryProvider.future),
    ref.watch(trainingProfileProvider.future),
    ref.watch(strengthBaselinesProvider.future),
  ).wait;
  return CoachEngine(
    catalog: catalog,
    inventory: inventory,
    history: history,
    profile: profile,
    baselines: baselines,
  );
});

final coachBriefProvider = FutureProvider<CoachBrief>((ref) async {
  final engine = await ref.watch(coachEngineProvider.future);
  return engine.brief(asOf: calendarDay(DateTime.now()));
});

/// This week's plan with the user's swaps laid over it.
final weeklyPlanProvider = FutureProvider<WeeklyPlan>((ref) async {
  final engine = await ref.watch(coachEngineProvider.future);
  final swaps = await ref.watch(planSwapsProvider.future);
  final plan = generateWeeklyPlan(
    engine: engine,
    asOf: calendarDay(DateTime.now()),
  );
  return applySwaps(plan, swaps, engine: engine);
});

/// This week's swaps. Writes are optimistic: the swap shows at once, and a
/// failed save (offline, or migration 0009 not applied yet) keeps it for this
/// session rather than snapping the plan back.
class PlanSwapsController extends AsyncNotifier<List<PlanSwap>> {
  @override
  Future<List<PlanSwap>> build() async {
    final monday = mondayOf(calendarDay(DateTime.now()));
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    try {
      return await ref
          .watch(workoutRepositoryProvider)
          .fetchSwaps(monday, sunday);
    } catch (error) {
      debugPrint('plan swaps unavailable: $error');
      return const [];
    }
  }

  /// Replaces [originalExerciseId] with [replacementExerciseId] on [day].
  /// Returns false when the swap could not be saved to the server.
  Future<bool> swap({
    required DateTime day,
    required String originalExerciseId,
    required String replacementExerciseId,
  }) async {
    final current = await future;
    final next = PlanSwap(
      planDate: calendarDay(day),
      originalExerciseId: originalExerciseId,
      replacementExerciseId: replacementExerciseId,
    );
    state = AsyncData([
      for (final s in current)
        if (!_sameSlot(s, next)) s,
      next,
    ]);
    try {
      await ref.read(workoutRepositoryProvider).saveSwap(next);
      return true;
    } catch (error) {
      debugPrint('plan swap not saved: $error');
      return false;
    }
  }

  /// Puts the plan's original exercise back.
  Future<void> undo({
    required DateTime day,
    required String originalExerciseId,
  }) async {
    final current = await future;
    final target = calendarDay(day);
    state = AsyncData([
      for (final s in current)
        if (!(s.planDate == target &&
            s.originalExerciseId == originalExerciseId))
          s,
    ]);
    try {
      await ref
          .read(workoutRepositoryProvider)
          .deleteSwap(target, originalExerciseId);
    } catch (error) {
      debugPrint('plan swap not removed: $error');
    }
  }

  static bool _sameSlot(PlanSwap a, PlanSwap b) =>
      a.planDate == b.planDate && a.originalExerciseId == b.originalExerciseId;
}

final planSwapsProvider =
    AsyncNotifierProvider<PlanSwapsController, List<PlanSwap>>(
      PlanSwapsController.new,
    );

/// Gemini's phrasing of the brief, already validated server-side.
final class CoachInsights {
  const CoachInsights({
    this.summary,
    this.nextLoadTips = const {},
    this.muscleGapTips = const {},
    this.model,
  });

  factory CoachInsights.fromJson(Map<String, dynamic> json) {
    final gaps = <String, ({String exerciseSlug, String tip})>{};
    final rawGaps = json['muscle_gaps'];
    if (rawGaps is Map) {
      for (final MapEntry(:key, :value) in rawGaps.entries) {
        if (value is Map &&
            value['exercise_slug'] is String &&
            value['tip'] is String) {
          gaps[key as String] = (
            exerciseSlug: value['exercise_slug'] as String,
            tip: value['tip'] as String,
          );
        }
      }
    }
    final rawLoads = json['next_loads'];
    return CoachInsights(
      summary: json['summary'] as String?,
      nextLoadTips: {
        if (rawLoads is Map)
          for (final MapEntry(:key, :value) in rawLoads.entries)
            if (value is String) key as String: value,
      },
      muscleGapTips: gaps,
      model: json['model'] as String?,
    );
  }

  final String? summary;

  /// exercise slug -> tip.
  final Map<String, String> nextLoadTips;

  /// muscle wire name -> the exercise the model picked and why.
  final Map<String, ({String exerciseSlug, String tip})> muscleGapTips;
  final String? model;
}

/// Null when the function is not deployed, the key is not set, Gemini fails,
/// or there is nothing to phrase. Never an error: the AI layer is optional.
final coachInsightsProvider = FutureProvider<CoachInsights?>((ref) async {
  final brief = await ref.watch(coachBriefProvider.future);
  if (brief.isEmpty) return null;
  try {
    final response = await ref
        .watch(supabaseClientProvider)
        .functions
        .invoke('coach-insights', body: brief.toJson());
    if (response.status != 200 || response.data is! Map) return null;
    return CoachInsights.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  } catch (error) {
    // 404 (not deployed), 503 (no key), network - all mean "no AI text".
    debugPrint('coach-insights unavailable: $error');
    return null;
  }
});
