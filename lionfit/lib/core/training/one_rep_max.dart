/// Estimated one-rep max (e1RM).
///
/// Every number here is arithmetic on what the lifter logged. No model, no
/// guess, no LLM: given the same set, this returns the same e1RM forever, which
/// is what makes "try 145" explainable and testable.
///
/// ## The formulas
///
/// **Epley (1985)** - Epley, B. *Poundage Chart*. Boyd Epley Workout, Body
/// Enterprises, University of Nebraska-Lincoln.
///
/// ```
/// e1RM = load * (1 + reps / 30)
/// ```
///
/// **Brzycki (1993)** - Brzycki, M. "Strength testing: predicting a one-rep max
/// from reps-to-fatigue". *JOPERD* 64(1): 88-90.
///
/// ```
/// e1RM = load * 36 / (37 - reps)
/// ```
///
/// ## Which one LionFit uses, and why
///
/// **Default: Epley** ([defaultE1rmFormula]). Reasons, in order:
///
/// 1. **It has no pole.** Brzycki's denominator is `37 - reps`: at 36 reps it
///    multiplies the load by 36, and at 37 reps it divides by zero. LionFit logs
///    high-rep sets (bodyweight circuits, 20-rep squats, outdoor work), so a
///    formula that explodes inside the app's own rep range is a liability.
/// 2. **They agree where it matters.** At 10 reps both give `1.333 * load`
///    exactly, so choosing Epley costs nothing in the 5-10 rep band.
/// 3. **It degrades gracefully above 10.** At 15 reps Epley says 1.50x and
///    Brzycki says 1.64x; at 20 reps, 1.67x versus 2.12x. Brzycki's inflation
///    past ~10 reps would hand a beginner a 20 lb jump off one high-rep set.
///
/// **Where each one breaks down:**
///
/// * **Brzycki** is good from 1 to ~10 reps (it returns the load exactly at 1
///   rep, which Epley does not) and should not be trusted past
///   [E1rmFormula.reliableRepCeiling] = 10.
/// * **Epley** overestimates a true single by 3.3%, so [epleyE1rm] returns the
///   load unchanged at 1 rep - a single *is* a 1RM. Above ~15 reps every
///   rep-max formula is extrapolation: the limiting factor becomes local
///   endurance, not maximal strength.
/// * **Both** assume the set was taken **to failure**. Most logged sets are not,
///   which is exactly what [effortAdjustedE1rm] fixes.
///
/// ## The RPE/RIR-based estimate
///
/// A set of `r` reps stopped with `k` reps in reserve is, as far as the load is
/// concerned, roughly a maximal set of `r + k` reps. So:
///
/// ```
/// e1RM = formula(load, reps + repsInReserve)      with RIR = 10 - RPE
/// ```
///
/// This is the standard RPE-chart relationship (Tuchscherer, M. *The Reactive
/// Training Manual*, 2008; validated for RIR accuracy by Zourdos et al. 2016,
/// J Strength Cond Res 30(1):267-275). **It is more accurate than a bare rep-max
/// formula at high rep counts**, for two reasons:
///
/// * Epley and Brzycki were both derived from sets taken to **true failure**.
///   Feeding them a set that stopped three reps short violates their premise,
///   and LionFit's logs are full of such sets - a hypertrophy block is mostly
///   programmed at RPE 7-8. Without the RIR term the engine systematically
///   under-reads the lifter and under-loads the next session.
/// * Above ~10-12 reps the rep-max curve itself is extrapolation and least
///   trustworthy, while proximity to failure stays a well-defined, directly
///   reported quantity. The further out the rep count, the more of the estimate
///   rests on the part we actually measured.
///
/// Wherever the lifter logged an effort rating, use this.
///
/// Credited reps in reserve are clamped at [maxCreditedRepsInReserve]: self-
/// reported RIR gets unreliable above ~5 (lifters are poor at judging how many
/// reps are left when the answer is "lots"), and crediting RIR 9 would let one
/// easy set imply an enormous 1RM.
library;

import 'models.dart';

/// Rep-max formulas this app knows.
enum E1rmFormula {
  /// `load * (1 + reps / 30)`. The LionFit default.
  epley('Epley', 15),

  /// `load * 36 / (37 - reps)`. Accurate to about 10 reps, then it inflates.
  brzycki('Brzycki', 10);

  const E1rmFormula(this.displayName, this.reliableRepCeiling);

  final String displayName;

  /// Above this rep count the estimate is extrapolation and should be labelled
  /// as such in the UI rather than presented as a measurement.
  final int reliableRepCeiling;
}

/// The formula LionFit uses unless a caller says otherwise. See the library doc
/// comment for the reasoning.
const E1rmFormula defaultE1rmFormula = E1rmFormula.epley;

/// Ceiling on self-reported reps in reserve credited toward an e1RM estimate.
const double maxCreditedRepsInReserve = 5;

/// Brzycki's formula divides by `37 - reps`; at and above this it is undefined
/// or absurd.
const int brzyckiRepLimit = 36;

/// Epley: `e1RM = load * (1 + reps / 30)`.
///
/// Returns [loadLb] unchanged for a single, where the raw formula would
/// overshoot by 3.3%.
double epleyE1rm({required double loadLb, required int reps}) {
  _checkInputs(loadLb, reps);
  if (reps <= 1) {
    return loadLb;
  }
  return loadLb * (1 + reps / 30);
}

/// Brzycki: `e1RM = load * 36 / (37 - reps)`.
///
/// Throws [ArgumentError] at or above [brzyckiRepLimit] reps, where the formula
/// divides by zero or multiplies the load by 36. Treat anything past
/// [E1rmFormula.reliableRepCeiling] as unreliable, not merely finite.
double brzyckiE1rm({required double loadLb, required int reps}) {
  _checkInputs(loadLb, reps);
  if (reps >= brzyckiRepLimit) {
    throw ArgumentError.value(
      reps,
      'reps',
      'Brzycki is undefined at $brzyckiRepLimit+ reps (it divides by 37 - reps); '
          'use E1rmFormula.epley for high-rep sets',
    );
  }
  if (reps <= 1) {
    return loadLb;
  }
  return loadLb * 36 / (37 - reps);
}

/// Estimated 1RM from a set taken to failure.
double estimateE1rm({
  required double loadLb,
  required int reps,
  E1rmFormula formula = defaultE1rmFormula,
}) => switch (formula) {
  E1rmFormula.epley => epleyE1rm(loadLb: loadLb, reps: reps),
  E1rmFormula.brzycki => brzyckiE1rm(loadLb: loadLb, reps: reps),
};

/// Estimated 1RM from a set that was **not** taken to failure.
///
/// `reps + repsInReserve` is the maximal set this one is equivalent to; see the
/// library doc comment. [repsInReserve] is clamped to
/// [maxCreditedRepsInReserve].
double effortAdjustedE1rm({
  required double loadLb,
  required int reps,
  required double repsInReserve,
  E1rmFormula formula = defaultE1rmFormula,
}) {
  if (repsInReserve.isNaN || repsInReserve < 0) {
    throw ArgumentError.value(
      repsInReserve,
      'repsInReserve',
      'Must be zero or more',
    );
  }
  final credited = repsInReserve > maxCreditedRepsInReserve
      ? maxCreditedRepsInReserve
      : repsInReserve;
  // Fractional RIR (RPE 7.5 -> 2.5) is interpolated linearly between the two
  // whole-rep estimates rather than rounded away.
  final floorReps = reps + credited.floor();
  final fraction = credited - credited.floor();
  final low = estimateE1rm(loadLb: loadLb, reps: floorReps, formula: formula);
  if (fraction == 0) {
    return low;
  }
  final high = estimateE1rm(
    loadLb: loadLb,
    reps: floorReps + 1,
    formula: formula,
  );
  return low + (high - low) * fraction;
}

/// Estimated 1RM for one logged set, in pounds.
///
/// Uses [effortAdjustedE1rm] when the lifter rated the set and the plain
/// rep-max formula when they did not. Returns `null` for sets no estimate can
/// be made from: zero reps (a failed set at the very first rep) or zero load
/// (bodyweight work, where the load is the lifter and is not in this table).
double? e1rmForSet(LoggedSet set, {E1rmFormula formula = defaultE1rmFormula}) {
  if (set.reps <= 0 || set.weightLb <= 0) {
    return null;
  }
  final effort = set.effort;
  if (effort == null) {
    // No rating: assume the set was taken to failure. That *underestimates* the
    // lifter if they had reps left, which is the safe direction to be wrong in.
    return estimateE1rm(loadLb: set.weightLb, reps: set.reps, formula: formula);
  }
  return effortAdjustedE1rm(
    loadLb: set.weightLb,
    reps: set.reps,
    repsInReserve: effort.repsInReserve,
    formula: formula,
  );
}

/// The load that should allow [reps] reps with [repsInReserve] left over,
/// given an [e1rmLb]. The inverse of [effortAdjustedE1rm].
///
/// This is how the progression engine turns "you can do about 185" into "so load
/// 150 for your set of 8 with a couple left in the tank".
double loadForReps({
  required double e1rmLb,
  required int reps,
  double repsInReserve = 0,
  E1rmFormula formula = defaultE1rmFormula,
}) {
  if (e1rmLb.isNaN || e1rmLb < 0) {
    throw ArgumentError.value(e1rmLb, 'e1rmLb', 'Must be zero or more');
  }
  if (reps < 1) {
    throw ArgumentError.value(reps, 'reps', 'Must be at least 1');
  }
  return e1rmLb *
      percentOfE1rm(reps: reps, repsInReserve: repsInReserve, formula: formula);
}

/// Fraction of 1RM a set of [reps] with [repsInReserve] left represents, 0-1.
///
/// `percentOfE1rm(reps: 1)` is 1.0; `percentOfE1rm(reps: 10)` is 0.75 under
/// Epley.
double percentOfE1rm({
  required int reps,
  double repsInReserve = 0,
  E1rmFormula formula = defaultE1rmFormula,
}) {
  if (reps < 1) {
    throw ArgumentError.value(reps, 'reps', 'Must be at least 1');
  }
  // Work from a nominal 100 lb lift: the ratio is scale-free.
  final e1rm = effortAdjustedE1rm(
    loadLb: 100,
    reps: reps,
    repsInReserve: repsInReserve,
    formula: formula,
  );
  return 100 / e1rm;
}

void _checkInputs(double loadLb, int reps) {
  if (loadLb.isNaN || loadLb.isInfinite || loadLb < 0) {
    throw ArgumentError.value(
      loadLb,
      'loadLb',
      'Must be a finite, non-negative load',
    );
  }
  if (reps < 1) {
    throw ArgumentError.value(
      reps,
      'reps',
      'An e1RM needs at least one completed rep',
    );
  }
}
