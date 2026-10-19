// Estimated 1RM: where the formulas agree, where they break down, and what the
// engine does with a set that was never taken to failure.
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/core/training/one_rep_max.dart';

void main() {
  group('the rep-max formulas', () {
    test('agree exactly at ten reps', () {
      // Epley: 100 * (1 + 10/30) = 133.33. Brzycki: 100 * 36/27 = 133.33.
      expect(
        epleyE1rm(loadLb: 100, reps: 10),
        closeTo(brzyckiE1rm(loadLb: 100, reps: 10), 1e-9),
      );
      expect(epleyE1rm(loadLb: 100, reps: 10), closeTo(133.333, 0.001));
    });

    test('treat a single as its own one-rep max', () {
      // Raw Epley would overshoot a true single by 3.3%.
      expect(epleyE1rm(loadLb: 225, reps: 1), 225);
      expect(brzyckiE1rm(loadLb: 225, reps: 1), 225);
    });

    test('diverge above ten reps, where Brzycki inflates', () {
      final epley = epleyE1rm(loadLb: 100, reps: 20);
      final brzycki = brzyckiE1rm(loadLb: 100, reps: 20);
      expect(epley, closeTo(166.667, 0.001));
      expect(brzycki, closeTo(211.765, 0.001));
      expect(
        brzycki - epley,
        greaterThan(40),
        reason:
            'a 45 lb difference off one set of 20 is why Epley is the '
            'default',
      );
    });

    test('publish the rep count past which each stops being trustworthy', () {
      expect(E1rmFormula.brzycki.reliableRepCeiling, 10);
      expect(E1rmFormula.epley.reliableRepCeiling, 15);
      expect(defaultE1rmFormula, E1rmFormula.epley);
    });

    test('refuse the rep counts where Brzycki divides by zero', () {
      expect(() => brzyckiE1rm(loadLb: 100, reps: 37), throwsArgumentError);
      expect(() => brzyckiE1rm(loadLb: 100, reps: 36), throwsArgumentError);
      // Epley has no pole, so a 30-rep bodyweight set still returns a number.
      expect(epleyE1rm(loadLb: 100, reps: 40), closeTo(233.333, 0.001));
    });

    test('refuse a set with no completed reps', () {
      expect(() => epleyE1rm(loadLb: 100, reps: 0), throwsArgumentError);
      expect(() => epleyE1rm(loadLb: -5, reps: 5), throwsArgumentError);
    });
  });

  group('the effort-adjusted estimate', () {
    test(
      'rates a set with reps left over higher than the same set to failure',
      () {
        final toFailure = estimateE1rm(loadLb: 100, reps: 10);
        final threeLeft = effortAdjustedE1rm(
          loadLb: 100,
          reps: 10,
          repsInReserve: 3,
        );
        expect(threeLeft, greaterThan(toFailure));
        // Equivalent to a maximal set of 13.
        expect(threeLeft, closeTo(epleyE1rm(loadLb: 100, reps: 13), 1e-9));
      },
    );

    test('reads RPE 7 and three reps in reserve as the same set', () {
      final viaRpe = Effort.rpe(7);
      final viaRir = Effort.rir(3);
      expect(
        effortAdjustedE1rm(
          loadLb: 135,
          reps: 10,
          repsInReserve: viaRpe.repsInReserve,
        ),
        closeTo(
          effortAdjustedE1rm(
            loadLb: 135,
            reps: 10,
            repsInReserve: viaRir.repsInReserve,
          ),
          1e-9,
        ),
      );
    });

    test('interpolates a half-point RPE instead of rounding it away', () {
      // RPE 7.5 is 2.5 reps in reserve: halfway between a 12- and a 13-rep set.
      final half = effortAdjustedE1rm(
        loadLb: 100,
        reps: 10,
        repsInReserve: Effort.rpe(7.5).repsInReserve,
      );
      expect(half, closeTo(141.667, 0.001));
    });

    test(
      'stops crediting reps in reserve past the point lifters can judge',
      () {
        expect(
          effortAdjustedE1rm(loadLb: 100, reps: 5, repsInReserve: 9),
          closeTo(
            effortAdjustedE1rm(
              loadLb: 100,
              reps: 5,
              repsInReserve: maxCreditedRepsInReserve,
            ),
            1e-9,
          ),
        );
      },
    );

    test('corrects the failure assumption a bare rep-max formula makes', () {
      // Both formulas were derived from sets taken to failure. A 15-rep set
      // stopped with 3 left is not that set, and ignoring the rating costs the
      // lifter 10 lb of estimated capability - which becomes a lighter
      // prescription next session.
      final assumedToFailure = estimateE1rm(loadLb: 100, reps: 15);
      final asReported = effortAdjustedE1rm(
        loadLb: 100,
        reps: 15,
        repsInReserve: 3,
      );
      expect(assumedToFailure, closeTo(150, 1e-9));
      expect(asReported, closeTo(160, 1e-9));
      expect(
        loadForReps(e1rmLb: asReported, reps: 8),
        greaterThan(loadForReps(e1rmLb: assumedToFailure, reps: 8)),
      );
    });
  });

  group('estimating from a logged set', () {
    LoggedSet set({
      required double weight,
      required int reps,
      Effort? effort,
    }) => LoggedSet(
      exerciseId: 'bench_press',
      setIndex: 0,
      setType: SetType.working,
      weight: weight,
      unit: WeightUnit.lb,
      reps: reps,
      effort: effort,
      performedAt: DateTime(2026, 10, 5),
    );

    test('uses the rating when the lifter gave one', () {
      final rated = set(weight: 135, reps: 10, effort: Effort.rir(3));
      expect(
        e1rmForSet(rated),
        closeTo(epleyE1rm(loadLb: 135, reps: 13), 1e-9),
      );
    });

    test('assumes an unrated set went to failure, which under-estimates', () {
      final unrated = set(weight: 135, reps: 10);
      expect(
        e1rmForSet(unrated),
        closeTo(epleyE1rm(loadLb: 135, reps: 10), 1e-9),
      );
      expect(
        e1rmForSet(unrated)!,
        lessThan(
          e1rmForSet(set(weight: 135, reps: 10, effort: Effort.rir(3)))!,
        ),
        reason: 'being wrong in the conservative direction is the point',
      );
    });

    test('has no answer for a failed set or for bodyweight work', () {
      expect(
        e1rmForSet(set(weight: 185, reps: 0, effort: Effort.rpe(10))),
        isNull,
      );
      expect(e1rmForSet(set(weight: 0, reps: 10)), isNull);
    });

    test('converts a kilogram log before estimating', () {
      final metric = LoggedSet(
        exerciseId: 'bench_press',
        setIndex: 0,
        setType: SetType.working,
        weight: 60,
        unit: WeightUnit.kg,
        reps: 5,
        performedAt: DateTime(2026, 10, 5),
      );
      expect(
        e1rmForSet(metric),
        closeTo(epleyE1rm(loadLb: 132.2774, reps: 5), 0.001),
      );
    });
  });

  group('working backwards from an estimate', () {
    test('a load for a rep target inverts the estimate', () {
      final e1rm = epleyE1rm(loadLb: 100, reps: 10);
      expect(loadForReps(e1rmLb: e1rm, reps: 10), closeTo(100, 1e-9));
    });

    test('leaving reps in the tank asks for a lighter bar', () {
      final e1rm = epleyE1rm(loadLb: 200, reps: 5);
      final toFailure = loadForReps(e1rmLb: e1rm, reps: 8);
      final withTwoLeft = loadForReps(e1rmLb: e1rm, reps: 8, repsInReserve: 2);
      expect(withTwoLeft, lessThan(toFailure));
    });

    test('a single is 100% of the one-rep max', () {
      expect(percentOfE1rm(reps: 1), closeTo(1, 1e-9));
      expect(percentOfE1rm(reps: 10), closeTo(0.75, 1e-9));
    });

    test('refuses a rep target below one', () {
      expect(() => loadForReps(e1rmLb: 200, reps: 0), throwsArgumentError);
      expect(() => percentOfE1rm(reps: 0), throwsArgumentError);
    });
  });
}
