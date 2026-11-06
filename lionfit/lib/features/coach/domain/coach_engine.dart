/// The recommendation layer: turns the user's logged sets into "what to do
/// next" - a next load for the lifts they already do, and exercises for the
/// muscles they have been neglecting.
///
/// ## Where the numbers come from
///
/// ```text
///  Supabase (RLS: own rows only)
///    workout_logs ─┐
///    exercises ────┼─> SetRecord / CatalogExercise / EquipmentItem
///    rec_center_   │        │
///    equipment ────┘        v
///                    CoachEngine (this file, pure Dart)
///                      ├─ ProgressionEngine   next load per exercise
///                      ├─ muscleStatusReport  which muscles are behind
///                      └─ EquipmentInventory  only gear that is on the floor,
///                                             loads snapped to that machine
///                           │
///                           v
///                    CoachBrief ──(slugs + numbers only)──> coach-insights
///                                                          Edge Function
///                                                          (Gemini phrasing)
/// ```
///
/// **Every number here is computed, never generated.** The LLM downstream is
/// only allowed to phrase what this file decided - see `docs/ai-coach.md`.
///
/// Pure Dart: no Flutter, no Supabase.
library;

import '../../../core/training/load_quantization.dart';
import '../../../core/training/models.dart';
import '../../../core/training/muscle_status.dart';
import '../../../core/training/one_rep_max.dart';
import '../../../core/training/progression.dart';
import '../../workout/domain/equipment_item.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/domain/workout_models.dart';
import 'starting_load.dart';

/// How a suggestion was arrived at, so the UI can be honest about it.
enum SuggestionBasis {
  /// The progression engine had at least two sessions to work from.
  progression,

  /// One session logged - repeat it once before adjusting.
  repeat,

  /// Never done - start at the lightest setting the equipment has.
  firstTime,

  /// Never done, but the onboarding survey gave something to estimate from.
  estimated,

  /// One rated session logged: the next load is worked out from how hard
  /// that session felt, rather than repeated.
  calibrated,

  /// No external load: progress by reps.
  bodyweight,

  /// Cardio: the reps field holds minutes.
  cardio,
}

/// One concrete, loggable prescription: "3 x 10 at 135 lb".
final class SuggestedSet {
  const SuggestedSet({
    required this.exercise,
    required this.unit,
    required this.reps,
    required this.sets,
    required this.basis,
    required this.reason,
    required this.targetReps,
    this.weight,
    this.action,
    this.equipmentLabel,
  });

  final CatalogExercise exercise;

  /// In [unit]. Null for bodyweight and cardio.
  final double? weight;
  final WeightUnit unit;

  /// Reps per set (minutes, for cardio).
  final int reps;
  final int sets;
  final RepRange targetReps;
  final SuggestionBasis basis;

  /// What the progression engine decided, when it decided anything.
  final ProgressionAction? action;

  /// One deterministic sentence explaining the number. The AI layer may
  /// rephrase it; it never changes the number.
  final String reason;

  /// The machine the load was rounded to ("Leg Extension").
  final String? equipmentLabel;

  String get prescription {
    final load = weight == null
        ? (basis == SuggestionBasis.cardio ? '' : 'bodyweight')
        : '${formatTrimmed(weight!)} ${unit.wireName}';
    if (basis == SuggestionBasis.cardio) return '$reps min';
    return '$sets × $reps · $load';
  }

  SuggestedSet copyWith({double? weight, int? reps, int? sets}) => SuggestedSet(
    exercise: exercise,
    unit: unit,
    reps: reps ?? this.reps,
    sets: sets ?? this.sets,
    basis: basis,
    reason: reason,
    targetReps: targetReps,
    weight: weight ?? this.weight,
    action: action,
    equipmentLabel: equipmentLabel,
  );
}

/// A muscle that is behind, with what to do about it.
final class MuscleGap {
  const MuscleGap({
    required this.group,
    required this.status,
    required this.hardSets,
    required this.target,
    required this.suggestions,
  });

  final MuscleGroup group;
  final MuscleTrainingStatus status;
  final double hardSets;
  final double target;
  final List<SuggestedSet> suggestions;
}

/// Everything the coach has to say, as data.
final class CoachBrief {
  const CoachBrief({
    required this.asOf,
    required this.goal,
    required this.nextLoads,
    required this.muscleGaps,
    required this.windowDays,
  });

  final DateTime asOf;
  final TrainingGoal goal;
  final int windowDays;
  final List<SuggestedSet> nextLoads;
  final List<MuscleGap> muscleGaps;

  bool get isEmpty => nextLoads.isEmpty && muscleGaps.isEmpty;

  /// The payload for the `coach-insights` Edge Function.
  ///
  /// **Slugs, enums and numbers only - no names, no notes, no free text.**
  /// The function looks names up itself from the database, so nothing the
  /// client sends can become prompt text. That is half of the grounding; the
  /// other half is in the function.
  Map<String, dynamic> toJson() => {
    'goal': goal.wireName,
    'window_days': windowDays,
    'next_loads': [
      for (final s in nextLoads)
        {
          'exercise_slug': s.exercise.slug,
          'basis': s.basis.name,
          'action': s.action?.wireName,
          'weight': s.weight,
          'unit': s.unit.wireName,
          'reps': s.reps,
          'sets': s.sets,
          'target_reps_min': s.targetReps.min,
          'target_reps_max': s.targetReps.max,
        },
    ],
    'muscle_gaps': [
      for (final gap in muscleGaps)
        {
          'muscle_group': gap.group.wireName,
          'status': gap.status.name,
          'hard_sets': (gap.hardSets * 10).round() / 10,
          'target_sets': (gap.target * 10).round() / 10,
          'candidate_slugs': [for (final s in gap.suggestions) s.exercise.slug],
        },
    ],
  };
}

/// Rep range by movement and goal. Compounds sit lower than isolation work;
/// weight loss sits higher across the board.
RepRange targetRepsFor(CatalogExercise exercise, TrainingGoal goal) {
  const compound = {
    'squat',
    'hinge',
    'lunge',
    'horizontal_push',
    'vertical_push',
    'horizontal_pull',
    'vertical_pull',
  };
  final isCompound = compound.contains(exercise.movementPattern);
  return switch (goal) {
    TrainingGoal.muscleGain =>
      isCompound ? const RepRange(6, 10) : const RepRange(10, 15),
    TrainingGoal.generalFitness =>
      isCompound ? const RepRange(8, 12) : const RepRange(10, 15),
    TrainingGoal.weightLoss =>
      isCompound ? const RepRange(10, 15) : const RepRange(12, 20),
  };
}

int targetSetsFor(TrainingGoal goal) => goal == TrainingGoal.muscleGain ? 4 : 3;

int cardioMinutesFor(TrainingGoal goal) =>
    goal == TrainingGoal.weightLoss ? 30 : 20;

final class CoachEngine {
  CoachEngine({
    required Iterable<CatalogExercise> catalog,
    required this.inventory,
    required Iterable<SetRecord> history,
    this.profile = const TrainingProfile(),
    Iterable<StrengthBaseline> baselines = const [],
    ProgressionEngine? progression,
  }) : _catalog = {for (final e in catalog) e.id: e},
       _history = List.unmodifiable(history),
       _baselines = List.unmodifiable(baselines),
       _progression =
           progression ??
           ProgressionEngine(
             config: ProgressionConfig(targetRepsInReserve: profile.targetRir),
           );

  final Map<String, CatalogExercise> _catalog;
  final EquipmentInventory inventory;
  final List<SetRecord> _history;
  final List<StrengthBaseline> _baselines;
  final TrainingProfile profile;
  final ProgressionEngine _progression;
  static final _fallbackQuantizers = LoadQuantizerRegistry.pennington();

  /// Survey-based first loads. Only consulted once the survey has been
  /// answered: without it, a first session starts at the lightest setting.
  late final StartingLoadEstimator? _starting =
      profile.experience == null && _baselines.isEmpty
      ? null
      : StartingLoadEstimator(
          baselines: _baselines,
          catalog: _catalog,
          experience: profile.experience,
          bodyweightLb: profile.bodyweightLb,
        );

  /// No sets logged before [day]. The plan treats that whole first week as
  /// calibration: fewer, easier sets, every one rated.
  bool isNewLifterOn(DateTime day) =>
      !_history.any((set) => set.performedOn.isBefore(day));

  late final Map<String, List<SetRecord>> _byExercise = () {
    final map = <String, List<SetRecord>>{};
    for (final set in _history) {
      map.putIfAbsent(set.exerciseId, () => []).add(set);
    }
    return map;
  }();

  CatalogExercise? exerciseById(String id) => _catalog[id];

  bool hasHistory(String exerciseId) => _byExercise.containsKey(exerciseId);

  /// [hasHistory], counting only sets logged before [day].
  bool hasHistoryBefore(String exerciseId, DateTime day) =>
      _byExercise[exerciseId]?.any((set) => set.performedOn.isBefore(day)) ??
      false;

  /// Active, and every piece of equipment it needs is on the floor.
  bool isAvailable(CatalogExercise exercise) =>
      exercise.isActive && inventory.allUsable(exercise.requiredEquipment);

  /// Every exercise that can be done today.
  Iterable<CatalogExercise> get available => _catalog.values.where(isAvailable);

  /// The next prescription for [exercise], from this user's own history.
  ///
  /// [before] limits that history to sets logged before a day. The plan
  /// passes the plan day, so today's prescription stays put while today's
  /// sets are being logged one by one instead of turning into next time's.
  SuggestedSet suggestFor(CatalogExercise exercise, {DateTime? before}) {
    final goal = profile.goal;
    final unit = profile.unit;
    final all = _byExercise[exercise.id] ?? const <SetRecord>[];
    final sets = before == null
        ? all
        : [
            for (final s in all)
              if (s.performedOn.isBefore(before)) s,
          ];
    final targetReps = targetRepsFor(exercise, goal);
    final setCount = targetSetsFor(goal);

    if (exercise.isCardio) {
      final lastMinutes = _lastWorkingReps(sets);
      return SuggestedSet(
        exercise: exercise,
        unit: unit,
        reps: lastMinutes ?? cardioMinutesFor(goal),
        sets: 1,
        targetReps: targetReps,
        basis: SuggestionBasis.cardio,
        reason: lastMinutes == null
            ? 'Start with ${cardioMinutesFor(goal)} minutes at a pace you '
                  'could hold a conversation at. Log the minutes as reps.'
            : 'Match last time ($lastMinutes min), or add a few minutes if it '
                  'felt easy. Log the minutes as reps.',
      );
    }

    final loadItem = inventory.loadBearing(exercise.requiredEquipment);
    final definition = exercise.toDefinition();
    final quantizer =
        loadItem?.quantizer ??
        _fallbackQuantizers.forEquipment(definition.equipment);
    final loggedAnyLoad = sets.any((s) => (s.weight ?? 0) > 0);
    final bodyweight =
        quantizer is BodyweightQuantizer ||
        (exercise.isBodyweightOnly && !loggedAnyLoad);

    if (bodyweight) {
      final last = _lastWorkingReps(sets);
      final reps = last == null
          ? targetReps.min
          : (last + 1).clamp(1, targetReps.max + 10);
      return SuggestedSet(
        exercise: exercise,
        unit: unit,
        reps: reps,
        sets: setCount,
        targetReps: targetReps,
        basis: SuggestionBasis.bodyweight,
        reason: last == null
            ? 'Bodyweight: aim for ${targetReps.min} clean reps per set.'
            : 'Last time your best set was $last reps. Try for one more.',
      );
    }

    // A survey answer given after the last logged session of this lift is
    // the freshest evidence there is: the user just told us what they can do
    // today. Older history must not override it.
    if (_freshBaselineSuggestion(
          exercise: exercise,
          sets: sets,
          targetReps: targetReps,
          quantizer: quantizer,
          setCount: setCount,
          equipmentLabel: loadItem?.label,
        )
        case final fromSurvey?) {
      return fromSurvey;
    }

    final history = ExerciseHistory(
      exerciseId: exercise.id,
      sets: sets.where((s) => s.reps != null).map((s) => s.toLoggedSet()),
    );
    final outcome = _progression.recommend(
      history: history,
      targetReps: targetReps,
      equipment: definition.equipment,
      displayUnit: unit,
      quantizer: quantizer,
    );
    final lastReps = history.workingSessions.isEmpty
        ? null
        : history.workingSessions.last.repsAtTopLoad;

    return switch (outcome) {
      LoadSuggestion(
        :final suggestedLoadLb,
        :final action,
        :final reason,
        :final previousLoadLb,
      ) =>
        SuggestedSet(
          exercise: exercise,
          unit: unit,
          weight: _display(suggestedLoadLb, unit),
          reps: switch (action) {
            // Same weight: chase one more rep, up to the top of the range.
            ProgressionAction.hold when suggestedLoadLb == previousLoadLb =>
              ((lastReps ?? targetReps.min) + 1).clamp(
                targetReps.min,
                targetReps.max,
              ),
            _ => targetReps.min,
          },
          sets: setCount,
          targetReps: targetReps,
          basis: SuggestionBasis.progression,
          action: action,
          reason: reason,
          equipmentLabel: loadItem?.label,
        ),
      NotEnoughData(:final repeatLoadLb, :final reason) =>
        repeatLoadLb != null
            ? _calibrated(
                    exercise: exercise,
                    history: history,
                    targetReps: targetReps,
                    quantizer: quantizer,
                    sets: setCount,
                    equipmentLabel: loadItem?.label,
                  ) ??
                  SuggestedSet(
                    exercise: exercise,
                    unit: unit,
                    weight: _display(repeatLoadLb, unit),
                    reps: lastReps ?? targetReps.min,
                    sets: setCount,
                    targetReps: targetReps,
                    basis: SuggestionBasis.repeat,
                    reason: reason,
                    equipmentLabel: loadItem?.label,
                  )
            : _estimatedFirst(
                    exercise: exercise,
                    targetReps: targetReps,
                    quantizer: quantizer,
                    sets: setCount,
                    equipmentLabel: loadItem?.label,
                  ) ??
                  SuggestedSet(
                    exercise: exercise,
                    unit: unit,
                    weight: _display(quantizer.minimumLoadLb, unit),
                    reps: targetReps.max,
                    sets: setCount,
                    targetReps: targetReps,
                    basis: SuggestionBasis.firstTime,
                    reason:
                        'First time on this one: the weight shown is the '
                        'lightest ${loadItem?.label ?? 'setting'} goes. Add '
                        'weight each set while ${targetReps.max} reps still '
                        'feel easy.',
                    equipmentLabel: loadItem?.label,
                  ),
    };
  }

  /// Available exercises that train [group] directly, best first.
  ///
  /// Cardio is left out unless [includeCardio]: a treadmill run does train
  /// calves, but it is not the answer to "my calves are behind".
  ///
  /// Ranking, in order: ones the user has done before (their next load is a
  /// real progression, not a guess), then the most targeted (fewest primary
  /// groups), then name for a stable order.
  List<CatalogExercise> candidatesFor(
    MuscleGroup group, {
    int limit = 3,
    Set<String> excludeIds = const {},
    bool includeCardio = false,
    DateTime? historyBefore,
  }) {
    final matches = [
      for (final exercise in _catalog.values)
        if (exercise.primaryMuscleGroups.contains(group) &&
            (includeCardio || !exercise.isCardio) &&
            !excludeIds.contains(exercise.id) &&
            isAvailable(exercise))
          exercise,
    ];
    // [historyBefore] keeps a week's plan stable: logging Monday's bench must
    // not reshuffle Wednesday, so the plan ranks by what was logged before
    // the week began.
    bool done(CatalogExercise e) => historyBefore == null
        ? hasHistory(e.id)
        : hasHistoryBefore(e.id, historyBefore);
    // Brand-new lifters get guided machines and dumbbells before a loaded
    // barbell, which takes coaching to do safely.
    final cautious = profile.experience == TrainingExperience.brandNew;
    int score(CatalogExercise e) =>
        (done(e) ? 2 : 0) + (cautious && !_isFreeBarbell(e) ? 1 : 0);
    matches.sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      if (byScore != 0) return byScore;
      final byFocus = a.primaryMuscleGroups.length.compareTo(
        b.primaryMuscleGroups.length,
      );
      if (byFocus != 0) return byFocus;
      return a.name.compareTo(b.name);
    });
    return matches.take(limit).toList(growable: false);
  }

  /// The groups that are behind in [report], worst first, each with
  /// [perGroup] ready-to-log suggestions.
  List<MuscleGap> gapsFrom(
    MuscleStatusReport report, {
    int maxGroups = 16,
    int perGroup = 2,
  }) {
    final behind =
        report.byMuscleGroup.values
            .where((e) => e.status != MuscleTrainingStatus.wellTrained)
            .toList()
          ..sort((a, b) {
            final byStatus = a.status.index.compareTo(b.status.index);
            return byStatus != 0
                ? byStatus
                : (a.hardSets / a.target).compareTo(b.hardSets / b.target);
          });
    return [
      for (final entry in behind.take(maxGroups))
        MuscleGap(
          group: entry.group,
          status: entry.status,
          hardSets: entry.hardSets,
          target: entry.target,
          suggestions: [
            for (final exercise in candidatesFor(entry.group, limit: perGroup))
              suggestFor(exercise),
          ],
        ),
    ];
  }

  /// The whole brief: next loads for what was trained in the last
  /// [recentDays], and the muscles behind over the last [windowDays].
  CoachBrief brief({
    required DateTime asOf,
    int windowDays = 7,
    int recentDays = 14,
    int maxNextLoads = 6,
    int maxGaps = 4,
  }) {
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    final since = today.subtract(Duration(days: recentDays - 1));
    final lastDone = <String, DateTime>{};
    for (final set in _history) {
      if (!set.setType.countsAsVolume || set.performedOn.isBefore(since)) {
        continue;
      }
      final seen = lastDone[set.exerciseId];
      if (seen == null || set.performedOn.isAfter(seen)) {
        lastDone[set.exerciseId] = set.performedOn;
      }
    }
    final recent = lastDone.keys.toList()
      ..sort((a, b) => lastDone[b]!.compareTo(lastDone[a]!));

    final report = muscleStatusReport(
      sets: _history.map((s) => s.toLoggedSet()),
      catalog: catalogOf(_catalog.values),
      asOf: today,
      windowDays: windowDays,
    );

    return CoachBrief(
      asOf: today,
      goal: profile.goal,
      windowDays: windowDays,
      nextLoads: [
        for (final id in recent)
          if (_catalog[id] case final exercise? when isAvailable(exercise))
            suggestFor(exercise),
      ].take(maxNextLoads).toList(growable: false),
      muscleGaps: gapsFrom(report, maxGroups: maxGaps),
    );
  }

  /// The working load from this exercise's own survey answer, when that
  /// answer is newer than every logged set of it and some history exists
  /// (with no history at all, [_estimatedFirst]'s easier calibration load
  /// applies instead). Target reps at the profile's target effort.
  SuggestedSet? _freshBaselineSuggestion({
    required CatalogExercise exercise,
    required List<SetRecord> sets,
    required RepRange targetReps,
    required LoadQuantizer quantizer,
    required int setCount,
    String? equipmentLabel,
  }) {
    if (sets.isEmpty) return null;
    StrengthBaseline? baseline;
    for (final b in _baselines) {
      if (b.exerciseId == exercise.id) baseline = b;
    }
    if (baseline == null || baseline.weightLb <= 0) return null;
    final answered = baseline.recordedAt ?? DateTime.now();
    final answeredDay = DateTime(answered.year, answered.month, answered.day);
    if (sets.any((s) => !s.performedOn.isBefore(answeredDay))) return null;

    final e1rm = estimateE1rm(
      loadLb: baseline.weightLb,
      reps: baseline.reps.clamp(1, 30),
    );
    final desired = loadForReps(
      e1rmLb: e1rm,
      reps: targetReps.min,
      repsInReserve: profile.targetRir,
    );
    final load = quantizer.quantize(
      desired.clamp(quantizer.minimumLoadLb, quantizer.maximumLoadLb),
      direction: RoundingDirection.down,
    );
    final unit = profile.unit;
    final shown = '${formatTrimmed(_display(load, unit))} ${unit.wireName}';
    return SuggestedSet(
      exercise: exercise,
      unit: unit,
      weight: _display(load, unit),
      reps: targetReps.min,
      sets: setCount,
      targetReps: targetReps,
      basis: SuggestionBasis.estimated,
      reason:
          'From your survey (${formatTrimmed(baseline.weight)} '
          '${baseline.unit.wireName} × ${baseline.reps}), which is newer than '
          'your last logged session: $shown for ${targetReps.min} at your '
          'target effort.',
      equipmentLabel: equipmentLabel,
    );
  }

  /// A first session's load from the survey, rounded down to a weight the
  /// equipment has. Null when there is no survey or nothing to estimate from.
  SuggestedSet? _estimatedFirst({
    required CatalogExercise exercise,
    required RepRange targetReps,
    required LoadQuantizer quantizer,
    required int sets,
    String? equipmentLabel,
  }) {
    final starting = _starting;
    if (starting == null) return null;
    final estimate = starting.estimate(exercise);
    final desired = starting.firstWorkingLoadLb(
      exercise,
      targetReps: targetReps,
      targetRir: profile.targetRir,
    );
    if (estimate == null || desired == null) return null;
    final load = quantizer.quantize(
      desired.clamp(quantizer.minimumLoadLb, quantizer.maximumLoadLb),
      direction: RoundingDirection.down,
    );
    final unit = profile.unit;
    final shown = formatTrimmed(_display(load, unit));
    return SuggestedSet(
      exercise: exercise,
      unit: unit,
      weight: _display(load, unit),
      reps: targetReps.max,
      sets: sets,
      targetReps: targetReps,
      basis: SuggestionBasis.estimated,
      reason:
          '${estimate.source} Start at $shown ${unit.wireName} for '
          '${targetReps.max} reps - it should feel easy. Rate each set and '
          'the next weight is worked out from it.',
      equipmentLabel: equipmentLabel,
    );
  }

  /// After exactly one session: if its top set was rated (RPE or RIR), work
  /// the next load out from that set's estimated 1RM at the profile's target
  /// effort, instead of just repeating it. Moves at most 20% either way.
  /// Null when the set was not rated, or the answer is the same load.
  SuggestedSet? _calibrated({
    required CatalogExercise exercise,
    required ExerciseHistory history,
    required RepRange targetReps,
    required LoadQuantizer quantizer,
    required int sets,
    String? equipmentLabel,
  }) {
    if (history.workingSessions.isEmpty) return null;
    final top = history.workingSessions.last.topWorkingSet;
    final effort = top?.effort;
    if (top == null || effort == null || top.weightLb <= 0) return null;
    final e1rm = e1rmForSet(top);
    if (e1rm == null) return null;
    final desired = loadForReps(
      e1rmLb: e1rm,
      reps: targetReps.min,
      repsInReserve: profile.targetRir,
    ).clamp(top.weightLb * 0.8, top.weightLb * 1.2);
    final load = quantizer.quantize(
      desired.clamp(quantizer.minimumLoadLb, quantizer.maximumLoadLb),
      direction: RoundingDirection.down,
    );
    if ((load - top.weightLb).abs() < 0.01) return null;
    final unit = profile.unit;
    final felt = effort is RpeEffort
        ? 'RPE ${formatTrimmed(effort.value)}'
        : '${formatTrimmed(effort.repsInReserve)} reps in reserve';
    final direction = load > top.weightLb
        ? 'That had room to spare, so go up'
        : 'That was harder than your target, so come down';
    return SuggestedSet(
      exercise: exercise,
      unit: unit,
      weight: _display(load, unit),
      reps: targetReps.min,
      sets: sets,
      targetReps: targetReps,
      basis: SuggestionBasis.calibrated,
      reason:
          'Last time: ${formatTrimmed(_display(top.weightLb, unit))} '
          '${unit.wireName} × ${top.reps} at $felt. $direction to '
          '${formatTrimmed(_display(load, unit))} ${unit.wireName} for '
          '${targetReps.min}.',
      equipmentLabel: equipmentLabel,
    );
  }

  /// Up to [limit] exercises to swap in for [original] on a plan day: same
  /// muscles, on equipment that is free, not already on the day.
  ///
  /// Ranking: same first muscle group, then same movement pattern, then
  /// most muscle overlap, then ones the user has done before, then name.
  /// Cardio swaps for other cardio.
  List<CatalogExercise> swapOptionsFor(
    CatalogExercise original, {
    Set<String> excludeIds = const {},
    int limit = 3,
  }) {
    final groups = original.primaryMuscleGroups.toSet();
    final first = original.primaryMuscleGroups.isEmpty
        ? null
        : original.primaryMuscleGroups.first;
    final matches = [
      for (final e in available)
        if (e.id != original.id &&
            !excludeIds.contains(e.id) &&
            e.isCardio == original.isCardio &&
            (original.isCardio || e.primaryMuscleGroups.any(groups.contains)))
          e,
    ];
    int score(CatalogExercise e) =>
        (first != null && e.primaryMuscleGroups.contains(first) ? 8 : 0) +
        (e.movementPattern == original.movementPattern ? 4 : 0) +
        e.primaryMuscleGroups.where(groups.contains).length +
        (hasHistory(e.id) ? 1 : 0);
    matches.sort((a, b) {
      final byScore = score(b).compareTo(score(a));
      return byScore != 0 ? byScore : a.name.compareTo(b.name);
    });
    return matches.take(limit).toList(growable: false);
  }

  static int? _lastWorkingReps(List<SetRecord> sets) {
    SetRecord? last;
    for (final set in sets) {
      if (!set.setType.countsAsVolume || set.reps == null) continue;
      if (last == null ||
          set.performedOn.isAfter(last.performedOn) ||
          (set.performedOn == last.performedOn &&
              (set.reps ?? 0) > (last.reps ?? 0))) {
        last = set;
      }
    }
    return last?.reps;
  }

  static bool _isFreeBarbell(CatalogExercise e) => e.requiredEquipment.any(
    const {
      'bench_press',
      'fixed_barbell',
      'deadlift_platform',
      'squat_rack',
    }.contains,
  );

  static double _display(double lb, WeightUnit unit) =>
      unit == WeightUnit.lb ? lb : roundToIncrement(unit.fromLb(lb), 0.5);
}
