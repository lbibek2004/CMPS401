/// Progressive overload: what to load next, and one sentence saying why.
///
/// The whole engine is arithmetic on the lifter's own logged sets. Same history
/// in, same number out, every time - an LLM is for phrasing, never for the
/// number.
///
/// ## The decision, in order
///
/// 1. **Not enough data.** Fewer than [ProgressionConfig.minSessionsForSuggestion]
///    sessions with a working set is no trend at all. The engine returns
///    [NotEnoughData] - an explicit outcome, not a null, not an extrapolation
///    from noise.
/// 2. **Accumulated fatigue.** RPE climbing while demonstrated performance stays
///    flat means the lifter is getting more tired, not stronger: hold. If
///    performance is actually falling while RPE climbs: deload.
/// 3. **Double progression.** Hit the top of the rep range -> add load. Landed
///    inside the range -> keep the load and add reps. Missed the bottom -> back
///    the load off.
/// 4. **Quantize.** Round the answer to a weight the Rec Center actually has
///    (see `load_quantization.dart`), rounding **down** on a progression not yet
///    earned and **up** when the lifter beat the target comfortably.
///
/// ## Guardrails
///
/// * **Never more than ~10% session to session** ([ProgressionConfig.maxSessionChangeFraction]),
///   whatever the math says, in either direction. The one documented exception:
///   when 10% is smaller than the smallest weight the equipment has (the 5 lb
///   dumbbell whose next neighbour is 10 lb), the engine may offer that single
///   smallest step - and only if the lifter's e1RM supports it. Otherwise it
///   holds and tells them to add reps. Without that exception a light dumbbell
///   user could never progress; without the cap a good day turns into a 25%
///   jump.
/// * **Sparse data is answered honestly**, never smoothed over.
/// * A missed target never produces an increase, however the e1RM math lands.
///
/// Fitness guidance only. Nothing here diagnoses, prescribes for an injury, or
/// reads a heart rate.
library;

import 'load_quantization.dart';
import 'models.dart';
import 'one_rep_max.dart';

/// Tunable thresholds. Defaults are the LionFit house rules.
final class ProgressionConfig {
  const ProgressionConfig({
    this.minSessionsForSuggestion = 2,
    this.minSessionsForTrend = 3,
    this.trendWindowSessions = 4,
    this.maxSessionChangeFraction = 0.10,
    this.targetRepsInReserve = 2,
    this.deloadFraction = 0.10,
    this.fatigueRpeSlopePerSession = 0.5,
    this.flatPerformanceSlopeFraction = 0.005,
    this.decliningPerformanceSlopeFraction = 0.01,
    this.formula = defaultE1rmFormula,
  });

  /// Sessions containing a working set before the engine will suggest a load.
  /// Below this it returns [NotEnoughData].
  final int minSessionsForSuggestion;

  /// Sessions needed before fatigue trends mean anything.
  final int minSessionsForTrend;

  /// How many recent sessions the trend is measured over.
  final int trendWindowSessions;

  /// The hard cap on session-to-session load change, as a fraction.
  final double maxSessionChangeFraction;

  /// How close to failure a working set should land: 2 reps in reserve is the
  /// hypertrophy default (RPE 8).
  final double targetRepsInReserve;

  /// How far a deload backs the load off.
  final double deloadFraction;

  /// RPE points per session that count as "effort is climbing".
  final double fatigueRpeSlopePerSession;

  /// Performance slope per session, as a fraction of mean e1RM, at or below
  /// which performance counts as flat.
  final double flatPerformanceSlopeFraction;

  /// Performance slope per session, as a fraction of mean e1RM, at or below
  /// which performance counts as actually declining.
  final double decliningPerformanceSlopeFraction;

  /// Rep-max formula used for every estimate. See `one_rep_max.dart`.
  final E1rmFormula formula;
}

/// What the engine is telling the lifter to do with the load.
enum ProgressionAction {
  increase('increase'),
  hold('hold'),
  reduce('reduce'),
  deload('deload');

  const ProgressionAction(this.wireName);

  final String wireName;
}

/// Why the engine is holding or backing off, when fatigue is the reason.
enum FatigueSignal {
  /// No fatigue pattern, or not enough rated sessions to see one.
  none,

  /// Effort climbing while demonstrated performance stays flat.
  effortRisingPerformanceFlat,

  /// Effort climbing while demonstrated performance falls.
  performanceDeclining,
}

/// The result of asking "what should I load next?".
///
/// Sealed rather than a nullable double: "we do not know yet" is a real answer
/// with its own explanation, and callers are forced to render it instead of
/// silently showing nothing.
sealed class ProgressionOutcome {
  const ProgressionOutcome({required this.exerciseId, required this.reason});

  final String exerciseId;

  /// One sentence, in the user's language, explaining the outcome.
  final String reason;
}

/// Too few sessions to say anything. Not an error - the normal state of a
/// brand-new exercise.
final class NotEnoughData extends ProgressionOutcome {
  const NotEnoughData({
    required super.exerciseId,
    required super.reason,
    required this.sessionsLogged,
    required this.sessionsRequired,
    this.repeatLoadLb,
  });

  /// Sessions with at least one straight working set.
  final int sessionsLogged;

  final int sessionsRequired;

  /// The load the lifter last used, when there is one - enough to pre-fill the
  /// logger so they can repeat it. `null` on a first-ever session.
  final double? repeatLoadLb;
}

/// A concrete load to put on the bar next session.
final class LoadSuggestion extends ProgressionOutcome {
  const LoadSuggestion({
    required super.exerciseId,
    required super.reason,
    required this.action,
    required this.suggestedLoadLb,
    required this.previousLoadLb,
    required this.targetReps,
    required this.basedOnSessions,
    required this.rawTargetLoadLb,
    required this.cappedByGuardrail,
    required this.effortWasMissing,
    required this.fatigueSignal,
    required this.equipmentDescription,
    required this.usesUnverifiedEquipmentData,
    required this.displayUnit,
    this.exceededGuardrailForSmallestStep = false,
    this.blockedByEquipmentStep = false,
  });

  final ProgressionAction action;

  /// The quantized answer, in the canonical unit.
  final double suggestedLoadLb;

  /// What they used last session, in the canonical unit.
  final double previousLoadLb;

  final RepRange targetReps;

  final int basedOnSessions;

  /// What the e1RM math asked for before the 10% cap and before quantization -
  /// kept so the cap is auditable rather than invisible.
  final double rawTargetLoadLb;

  /// `true` when the 10% guardrail, not the math, decided the number.
  final bool cappedByGuardrail;

  /// `true` when the lifter rated neither RPE nor RIR, so the engine took the
  /// conservative path.
  final bool effortWasMissing;

  final FatigueSignal fatigueSignal;

  /// Which quantizer produced the number, assumptions included.
  final String equipmentDescription;

  /// `true` when the equipment denominations behind this number are still
  /// unverified (plate set, stack spacing). Worth a UI footnote.
  final bool usesUnverifiedEquipmentData;

  final WeightUnit displayUnit;

  /// `true` in the documented exception where the smallest real increment on
  /// this equipment exceeds 10% and the lifter's e1RM supports taking it.
  final bool exceededGuardrailForSmallestStep;

  /// `true` when the lifter earned an increase but the next weight up is too
  /// big a jump to be safe, so the engine held instead.
  final bool blockedByEquipmentStep;

  /// The suggestion in the unit the user reads, rounded for display.
  Weight get suggestedLoad =>
      Weight.lb(suggestedLoadLb).to(displayUnit).rounded();

  /// Change from last session as a fraction, e.g. `0.0741` for 135 -> 145.
  double get changeFraction => previousLoadLb == 0
      ? 0
      : (suggestedLoadLb - previousLoadLb) / previousLoadLb;
}

/// Turns a logged history into the next load.
final class ProgressionEngine {
  ProgressionEngine({
    this.config = const ProgressionConfig(),
    LoadQuantizerRegistry? quantizers,
  }) : _quantizers = quantizers ?? LoadQuantizerRegistry.pennington();

  final ProgressionConfig config;
  final LoadQuantizerRegistry _quantizers;

  /// Recommends the next load for [history] against [targetReps].
  ///
  /// [equipment] selects the rounding table; pass [quantizer] to override it for
  /// one call. [displayUnit] affects the wording of [ProgressionOutcome.reason]
  /// only - the math and the snapping always happen in pounds, because that is
  /// what the plates are labelled in.
  ProgressionOutcome recommend({
    required ExerciseHistory history,
    required RepRange targetReps,
    required EquipmentType equipment,
    WeightUnit displayUnit = WeightUnit.lb,
    LoadQuantizer? quantizer,
  }) {
    final sessions = history.workingSessions;
    final effectiveQuantizer = quantizer ?? _quantizers.forEquipment(equipment);

    if (sessions.length < config.minSessionsForSuggestion) {
      return _notEnoughData(history.exerciseId, sessions, displayUnit);
    }

    final last = sessions.last;
    final previousLoadLb = last.topWorkingLoadLb!;
    final repsAchieved = last.repsAtTopLoad!;
    final effort = last.effortAtTopLoad;
    final missedTarget = targetReps.isBelowBottom(repsAchieved);

    final fatigue = _assessFatigue(sessions);

    if (fatigue == FatigueSignal.performanceDeclining) {
      return _deload(
        exerciseId: history.exerciseId,
        sessions: sessions,
        previousLoadLb: previousLoadLb,
        targetReps: targetReps,
        quantizer: effectiveQuantizer,
        displayUnit: displayUnit,
        effort: effort,
      );
    }

    if (fatigue == FatigueSignal.effortRisingPerformanceFlat && !missedTarget) {
      return _fatigueHold(
        exerciseId: history.exerciseId,
        sessions: sessions,
        previousLoadLb: previousLoadLb,
        targetReps: targetReps,
        quantizer: effectiveQuantizer,
        displayUnit: displayUnit,
      );
    }

    if (missedTarget) {
      return _backOff(
        exerciseId: history.exerciseId,
        sessions: sessions,
        previousLoadLb: previousLoadLb,
        repsAchieved: repsAchieved,
        effort: effort,
        targetReps: targetReps,
        quantizer: effectiveQuantizer,
        displayUnit: displayUnit,
        fatigue: fatigue,
      );
    }

    if (!targetReps.isAtOrAboveTop(repsAchieved)) {
      return _holdAndAddReps(
        exerciseId: history.exerciseId,
        sessions: sessions,
        previousLoadLb: previousLoadLb,
        repsAchieved: repsAchieved,
        targetReps: targetReps,
        quantizer: effectiveQuantizer,
        displayUnit: displayUnit,
        effort: effort,
      );
    }

    return _increase(
      exerciseId: history.exerciseId,
      sessions: sessions,
      previousLoadLb: previousLoadLb,
      repsAchieved: repsAchieved,
      effort: effort,
      targetReps: targetReps,
      quantizer: effectiveQuantizer,
      displayUnit: displayUnit,
      fatigue: fatigue,
    );
  }

  // --- outcomes -------------------------------------------------------------

  NotEnoughData _notEnoughData(
    String exerciseId,
    List<ExerciseSession> sessions,
    WeightUnit displayUnit,
  ) {
    final required = config.minSessionsForSuggestion;
    if (sessions.isEmpty) {
      return NotEnoughData(
        exerciseId: exerciseId,
        sessionsLogged: 0,
        sessionsRequired: required,
        reason:
            'This is your first time logging this one, so pick a weight you '
            'could handle for a couple more reps than the target and we will '
            'take it from there.',
      );
    }
    final lastLoad = sessions.last.topWorkingLoadLb!;
    return NotEnoughData(
      exerciseId: exerciseId,
      sessionsLogged: sessions.length,
      sessionsRequired: required,
      repeatLoadLb: lastLoad,
      reason:
          'One session logged at this exercise is not a trend yet - run '
          '${_load(lastLoad, displayUnit)} back once more and we will adjust '
          'from there.',
    );
  }

  LoadSuggestion _deload({
    required String exerciseId,
    required List<ExerciseSession> sessions,
    required double previousLoadLb,
    required RepRange targetReps,
    required LoadQuantizer quantizer,
    required WeightUnit displayUnit,
    required Effort? effort,
  }) {
    final raw = previousLoadLb * (1 - config.deloadFraction);
    final suggested = _quantizeReduction(
      quantizer: quantizer,
      target: raw,
      previousLoadLb: previousLoadLb,
    );
    final window = _window(sessions);
    return LoadSuggestion(
      exerciseId: exerciseId,
      action: ProgressionAction.deload,
      suggestedLoadLb: suggested,
      previousLoadLb: previousLoadLb,
      targetReps: targetReps,
      basedOnSessions: window.length,
      rawTargetLoadLb: raw,
      cappedByGuardrail: false,
      effortWasMissing: effort == null,
      fatigueSignal: FatigueSignal.performanceDeclining,
      equipmentDescription: quantizer.description,
      usesUnverifiedEquipmentData: quantizer.isUnverifiedAssumption,
      displayUnit: displayUnit,
      reason:
          'Your effort has been climbing while the reps slipped over the '
          'last ${window.length} sessions, so take a lighter week at '
          '${_load(suggested, displayUnit)} and let the fatigue clear.',
    );
  }

  LoadSuggestion _fatigueHold({
    required String exerciseId,
    required List<ExerciseSession> sessions,
    required double previousLoadLb,
    required RepRange targetReps,
    required LoadQuantizer quantizer,
    required WeightUnit displayUnit,
  }) {
    final window = _window(sessions);
    final firstRpe = window.first.effortAtTopLoad?.rpe;
    final lastRpe = window.last.effortAtTopLoad?.rpe;
    final climb = (firstRpe != null && lastRpe != null)
        ? 'climbed from RPE ${formatTrimmed(firstRpe)} to '
              'RPE ${formatTrimmed(lastRpe)}'
        : 'has been climbing';
    return LoadSuggestion(
      exerciseId: exerciseId,
      action: ProgressionAction.hold,
      suggestedLoadLb: previousLoadLb,
      previousLoadLb: previousLoadLb,
      targetReps: targetReps,
      basedOnSessions: window.length,
      rawTargetLoadLb: previousLoadLb,
      cappedByGuardrail: false,
      effortWasMissing: false,
      fatigueSignal: FatigueSignal.effortRisingPerformanceFlat,
      equipmentDescription: quantizer.description,
      usesUnverifiedEquipmentData: quantizer.isUnverifiedAssumption,
      displayUnit: displayUnit,
      reason:
          'Your effort $climb over the last ${window.length} sessions '
          'while the reps stayed flat - fatigue rather than readiness - so '
          'hold ${_load(previousLoadLb, displayUnit)} this week.',
    );
  }

  LoadSuggestion _backOff({
    required String exerciseId,
    required List<ExerciseSession> sessions,
    required double previousLoadLb,
    required int repsAchieved,
    required Effort? effort,
    required RepRange targetReps,
    required LoadQuantizer quantizer,
    required WeightUnit displayUnit,
    required FatigueSignal fatigue,
  }) {
    // A set they could not complete a single rep of gets the biggest cut the
    // guardrail allows - there is no rep count to estimate from.
    final raw = repsAchieved < 1
        ? previousLoadLb * (1 - config.maxSessionChangeFraction)
        : _targetLoadFromPerformance(
            loadLb: previousLoadLb,
            reps: repsAchieved,
            effort: effort,
            targetReps: targetReps,
          );
    // A miss never produces an increase, whatever the estimate says.
    final ceiling = previousLoadLb;
    final floor = previousLoadLb * (1 - config.maxSessionChangeFraction);
    final capped = raw.clamp(floor, ceiling).toDouble();
    final suggested = _quantizeReduction(
      quantizer: quantizer,
      target: capped,
      previousLoadLb: previousLoadLb,
    );
    final held = suggested >= previousLoadLb - 1e-6;
    final shortBy = targetReps.min - repsAchieved;
    final repWord = shortBy == 1 ? 'rep' : 'reps';
    return LoadSuggestion(
      exerciseId: exerciseId,
      action: held ? ProgressionAction.hold : ProgressionAction.reduce,
      suggestedLoadLb: suggested,
      previousLoadLb: previousLoadLb,
      targetReps: targetReps,
      basedOnSessions: sessions.length,
      rawTargetLoadLb: raw,
      cappedByGuardrail: raw < floor - 1e-6,
      effortWasMissing: effort == null,
      fatigueSignal: fatigue,
      equipmentDescription: quantizer.description,
      usesUnverifiedEquipmentData: quantizer.isUnverifiedAssumption,
      displayUnit: displayUnit,
      reason: held
          ? 'You stopped $shortBy $repWord short of $targetReps at '
                '${_load(previousLoadLb, displayUnit)}, so run the same weight '
                'back and finish the range.'
          : 'You got $repsAchieved reps at '
                '${_load(previousLoadLb, displayUnit)} and the target is '
                '$targetReps, so drop to ${_load(suggested, displayUnit)} and '
                'rebuild the range.',
    );
  }

  LoadSuggestion _holdAndAddReps({
    required String exerciseId,
    required List<ExerciseSession> sessions,
    required double previousLoadLb,
    required int repsAchieved,
    required RepRange targetReps,
    required LoadQuantizer quantizer,
    required WeightUnit displayUnit,
    required Effort? effort,
  }) {
    return LoadSuggestion(
      exerciseId: exerciseId,
      action: ProgressionAction.hold,
      suggestedLoadLb: previousLoadLb,
      previousLoadLb: previousLoadLb,
      targetReps: targetReps,
      basedOnSessions: sessions.length,
      rawTargetLoadLb: previousLoadLb,
      cappedByGuardrail: false,
      effortWasMissing: effort == null,
      fatigueSignal: FatigueSignal.none,
      equipmentDescription: quantizer.description,
      usesUnverifiedEquipmentData: quantizer.isUnverifiedAssumption,
      displayUnit: displayUnit,
      reason:
          'You got $repsAchieved of $targetReps at '
          '${_load(previousLoadLb, displayUnit)}, so stay there and add reps '
          'before you add weight.',
    );
  }

  LoadSuggestion _increase({
    required String exerciseId,
    required List<ExerciseSession> sessions,
    required double previousLoadLb,
    required int repsAchieved,
    required Effort? effort,
    required RepRange targetReps,
    required LoadQuantizer quantizer,
    required WeightUnit displayUnit,
    required FatigueSignal fatigue,
  }) {
    final capLb = previousLoadLb * config.maxSessionChangeFraction;
    final smallestStep = quantizer.stepUp(previousLoadLb);

    if (effort == null) {
      // No rating: take the smallest real step, or hold if even that is a
      // bigger jump than the guardrail allows.
      final withinCap = smallestStep - previousLoadLb <= capLb + 1e-6;
      return LoadSuggestion(
        exerciseId: exerciseId,
        action: withinCap ? ProgressionAction.increase : ProgressionAction.hold,
        suggestedLoadLb: withinCap ? smallestStep : previousLoadLb,
        previousLoadLb: previousLoadLb,
        targetReps: targetReps,
        basedOnSessions: sessions.length,
        rawTargetLoadLb: smallestStep,
        cappedByGuardrail: !withinCap,
        effortWasMissing: true,
        fatigueSignal: fatigue,
        equipmentDescription: quantizer.description,
        usesUnverifiedEquipmentData: quantizer.isUnverifiedAssumption,
        displayUnit: displayUnit,
        blockedByEquipmentStep: !withinCap,
        reason: withinCap
            ? 'You finished $repsAchieved reps at '
                  '${_load(previousLoadLb, displayUnit)} without logging an RPE, '
                  'so take the smallest step up to '
                  '${_load(smallestStep, displayUnit)}.'
            : 'You finished the top of $targetReps at '
                  '${_load(previousLoadLb, displayUnit)}, but the next weight up '
                  'is ${_load(smallestStep, displayUnit)} - stay here and add '
                  'reps, or log an RPE so we can judge the jump.',
      );
    }

    final raw = _targetLoadFromPerformance(
      loadLb: previousLoadLb,
      reps: repsAchieved,
      effort: effort,
      targetReps: targetReps,
    );
    final cappedTarget = raw > previousLoadLb + capLb
        ? previousLoadLb + capLb
        : raw;
    final comfortable = effort.repsInReserve >= config.targetRepsInReserve;
    var suggested = quantizer.quantize(
      cappedTarget,
      direction: comfortable ? RoundingDirection.up : RoundingDirection.down,
    );
    // Rounding up must not smuggle the load past the guardrail.
    if (suggested > previousLoadLb + capLb + 1e-6) {
      suggested = quantizer.quantize(
        cappedTarget,
        direction: RoundingDirection.down,
      );
    }

    if (suggested <= previousLoadLb + 1e-6) {
      // 10% of this load is smaller than anything the equipment can add. Offer
      // the single smallest step only if the e1RM says they can still finish
      // the bottom of the range on it; otherwise hold and add reps.
      final e1rm = effortAdjustedE1rm(
        loadLb: previousLoadLb,
        reps: repsAchieved,
        repsInReserve: effort.repsInReserve,
        formula: config.formula,
      );
      final supported = loadForReps(
        e1rmLb: e1rm,
        reps: targetReps.min,
        formula: config.formula,
      );
      final canTakeStep =
          smallestStep <= supported + 1e-6 &&
          smallestStep > previousLoadLb + 1e-6;
      return LoadSuggestion(
        exerciseId: exerciseId,
        action: canTakeStep
            ? ProgressionAction.increase
            : ProgressionAction.hold,
        suggestedLoadLb: canTakeStep ? smallestStep : previousLoadLb,
        previousLoadLb: previousLoadLb,
        targetReps: targetReps,
        basedOnSessions: sessions.length,
        rawTargetLoadLb: raw,
        cappedByGuardrail: true,
        effortWasMissing: false,
        fatigueSignal: fatigue,
        equipmentDescription: quantizer.description,
        usesUnverifiedEquipmentData: quantizer.isUnverifiedAssumption,
        displayUnit: displayUnit,
        exceededGuardrailForSmallestStep: canTakeStep,
        blockedByEquipmentStep: !canTakeStep,
        reason: canTakeStep
            ? 'You hit $repsAchieved reps at ${effort.label} and the next '
                  'weight up is ${_load(smallestStep, displayUnit)} - a bigger '
                  'jump than we normally allow, but the smallest this equipment '
                  'has, so take it and expect fewer reps.'
            : 'You hit $repsAchieved reps at ${effort.label}, but the next '
                  'weight up is ${_load(smallestStep, displayUnit)} and that is '
                  'too big a jump from ${_load(previousLoadLb, displayUnit)} - '
                  'stay here and add reps.',
      );
    }

    final capped = raw > previousLoadLb + capLb + 1e-6;
    return LoadSuggestion(
      exerciseId: exerciseId,
      action: ProgressionAction.increase,
      suggestedLoadLb: suggested,
      previousLoadLb: previousLoadLb,
      targetReps: targetReps,
      basedOnSessions: sessions.length,
      rawTargetLoadLb: raw,
      cappedByGuardrail: capped,
      effortWasMissing: false,
      fatigueSignal: fatigue,
      equipmentDescription: quantizer.description,
      usesUnverifiedEquipmentData: quantizer.isUnverifiedAssumption,
      displayUnit: displayUnit,
      reason: capped
          ? 'You hit $repsAchieved reps at ${effort.label} with about '
                '${formatTrimmed(effort.repsInReserve)} left in the tank - the '
                'math says more, but we cap jumps at '
                '${(config.maxSessionChangeFraction * 100).round()}%, so try '
                '${_load(suggested, displayUnit)}.'
          : 'You hit $repsAchieved reps at ${effort.label}, roughly '
                '${formatTrimmed(effort.repsInReserve)} reps left in the tank - '
                'try ${_load(suggested, displayUnit)}.',
    );
  }

  // --- math -----------------------------------------------------------------

  /// The load that should land the lifter at the bottom of [targetReps] with
  /// [ProgressionConfig.targetRepsInReserve] left over, given what they just
  /// did.
  ///
  /// Under double progression, adding weight resets you to the bottom of the
  /// range, so the bottom is what the next load is sized for.
  double _targetLoadFromPerformance({
    required double loadLb,
    required int reps,
    required Effort? effort,
    required RepRange targetReps,
  }) {
    final e1rm = effort == null
        ? estimateE1rm(loadLb: loadLb, reps: reps, formula: config.formula)
        : effortAdjustedE1rm(
            loadLb: loadLb,
            reps: reps,
            repsInReserve: effort.repsInReserve,
            formula: config.formula,
          );
    return loadForReps(
      e1rmLb: e1rm,
      reps: targetReps.min,
      repsInReserve: config.targetRepsInReserve,
      formula: config.formula,
    );
  }

  /// Snaps a reduction to a real weight **without breaching the guardrail**.
  ///
  /// Reductions round down, like any load not yet earned - but on a 5 lb
  /// barbell step, rounding a 10% cut down can land at 10.8%, and the cap is a
  /// cap in both directions. When that happens the next weight at or above the
  /// floor is taken instead: a slightly smaller back-off, never a larger one.
  double _quantizeReduction({
    required LoadQuantizer quantizer,
    required double target,
    required double previousLoadLb,
  }) {
    final floor = previousLoadLb * (1 - config.maxSessionChangeFraction);
    final rounded = quantizer.quantize(
      target,
      direction: RoundingDirection.down,
    );
    if (rounded >= floor - 1e-6) {
      return rounded;
    }
    final liftedToFloor = quantizer.quantize(
      floor,
      direction: RoundingDirection.up,
    );
    return liftedToFloor <= previousLoadLb ? liftedToFloor : previousLoadLb;
  }

  List<ExerciseSession> _window(List<ExerciseSession> sessions) =>
      sessions.length <= config.trendWindowSessions
      ? sessions
      : sessions.sublist(sessions.length - config.trendWindowSessions);

  /// Looks for accumulated fatigue: effort climbing while demonstrated
  /// performance does not.
  ///
  /// Performance is measured with the **unadjusted** rep-max estimate (load and
  /// reps only). That is deliberate: it is a record of what the lifter actually
  /// did, independent of how it felt, so "felt harder" and "did less" stay
  /// separate signals instead of collapsing into each other.
  FatigueSignal _assessFatigue(List<ExerciseSession> sessions) {
    final window = _window(sessions);
    if (window.length < config.minSessionsForTrend) {
      return FatigueSignal.none;
    }
    final rpe = <double>[];
    final performance = <double>[];
    for (final session in window) {
      final effort = session.effortAtTopLoad;
      final top = session.topWorkingSet;
      final reps = session.repsAtTopLoad;
      if (effort == null || top == null || reps == null) {
        // Without a rating on every session in the window there is no effort
        // trend to read, and guessing one is exactly what we refuse to do.
        return FatigueSignal.none;
      }
      rpe.add(effort.rpe);
      // A session where nothing was completed is credited no rep-max bonus at
      // all: the bare load, which is what `reps: 1` returns.
      performance.add(
        estimateE1rm(
          loadLb: top.weightLb,
          reps: reps < 1 ? 1 : reps,
          formula: config.formula,
        ),
      );
    }
    final rpeSlope = _slope(rpe);
    if (rpeSlope < config.fatigueRpeSlopePerSession) {
      return FatigueSignal.none;
    }
    final meanPerformance =
        performance.reduce((a, b) => a + b) / performance.length;
    if (meanPerformance <= 0) {
      return FatigueSignal.none;
    }
    final relativeSlope = _slope(performance) / meanPerformance;
    if (relativeSlope <= -config.decliningPerformanceSlopeFraction) {
      return FatigueSignal.performanceDeclining;
    }
    if (relativeSlope <= config.flatPerformanceSlopeFraction) {
      return FatigueSignal.effortRisingPerformanceFlat;
    }
    return FatigueSignal.none;
  }

  /// Least-squares slope of [values] against their index: change per session.
  static double _slope(List<double> values) {
    final n = values.length;
    if (n < 2) {
      return 0;
    }
    final meanX = (n - 1) / 2;
    final meanY = values.reduce((a, b) => a + b) / n;
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = i - meanX;
      numerator += dx * (values[i] - meanY);
      denominator += dx * dx;
    }
    return denominator == 0 ? 0 : numerator / denominator;
  }

  String _load(double lb, WeightUnit unit) {
    final weight = Weight.lb(lb).to(unit).rounded();
    return '${formatTrimmed(weight.value)} ${unit.wireName}';
  }
}
