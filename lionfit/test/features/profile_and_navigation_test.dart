import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/router/app_router.dart';
import 'package:lionfit/core/training/models.dart';
import 'package:lionfit/features/workout/domain/training_profile.dart';
import 'package:lionfit/features/workout/presentation/rest_timer.dart';

void main() {
  group('redirects', () {
    String? go(String to, {bool signedIn = true, bool survey = false}) =>
        redirectFor(location: to, signedIn: signedIn, needsOnboarding: survey);

    test('a signed-in user never sees the landing page', () {
      expect(go(Routes.landing), Routes.home);
      expect(go(Routes.login), Routes.home);
      expect(go(Routes.signUp), Routes.home);
    });

    test('signed out: public pages only', () {
      expect(go(Routes.landing, signedIn: false), isNull);
      expect(go(Routes.login, signedIn: false), isNull);
      expect(go(Routes.home, signedIn: false), Routes.landing);
      expect(go(Routes.profile, signedIn: false), Routes.landing);
    });

    test('the survey comes first when it is owed', () {
      expect(go(Routes.home, survey: true), Routes.welcome);
      expect(go(Routes.landing, survey: true), Routes.welcome);
      expect(go(Routes.welcome, survey: true), isNull);
    });

    test('the survey can be retaken once done', () {
      expect(go(Routes.welcome), isNull);
      expect(go(Routes.history), isNull);
    });
  });

  group('training profile row', () {
    test('without migration 0009 the survey is not demanded', () {
      final p = TrainingProfile.fromRow({
        'goal': 'muscle_gain',
        'days_per_week': 4,
        'unit_preference': 'kg',
        'effort_preference': 'rir',
        'display_name': 'Pao',
      });
      expect(p.hasExtendedColumns, isFalse);
      expect(p.needsOnboarding, isFalse);
      expect(p.toRow().keys, isNot(contains('w_number')));
      expect(p.displayName, 'Pao');
    });

    test('with the new columns and no completion stamp, it is owed', () {
      final p = TrainingProfile.fromRow({
        'goal': 'general_fitness',
        'days_per_week': 3,
        'onboarding_completed_at': null,
        'w_number': 'W0123456',
        'target_rpe': 7,
        'rest_timer_seconds': 120,
        'theme_preference': 'dark',
        'experience': 'beginner',
      });
      expect(p.needsOnboarding, isTrue);
      expect(p.targetRir, 3);
      expect(p.themePreference, ThemePreference.dark);
      expect(p.experience, TrainingExperience.beginner);
      final row = p.toRow();
      expect(row['w_number'], 'W0123456');
      expect(row['rest_timer_seconds'], 120);
    });

    test('W-number normalisation and format', () {
      expect(normalizeWNumber(' w0123456 '), 'W0123456');
      expect(normalizeWNumber('  '), isNull);
      expect(kWNumberPattern.hasMatch('W0123456'), isTrue);
      expect(kWNumberPattern.hasMatch('W012345'), isFalse);
      expect(kWNumberPattern.hasMatch('0123456W'), isFalse);
    });

    test('baselines convert to pounds', () {
      const b = StrengthBaseline(
        exerciseId: 'x',
        weight: 100,
        unit: WeightUnit.kg,
        reps: 5,
      );
      expect(b.weightLb, closeTo(220.46, 0.01));
    });
  });

  group('rest timer', () {
    testWidgets('counts down, +10s extends, buzzes 3 s once at the end', (
      tester,
    ) async {
      // testWidgets fakes timers; the clock is advanced by hand alongside.
      var now = DateTime(2026, 11, 5, 9);
      Future<void> elapse(int seconds) async {
        now = now.add(Duration(seconds: seconds));
        await tester.pump(Duration(seconds: seconds));
      }

      final buzzes = <Duration>[];
      final container = ProviderContainer(
        overrides: [
          restClockProvider.overrideWithValue(() => now),
          restVibrateProvider.overrideWithValue((d) async => buzzes.add(d)),
        ],
      );
      addTearDown(container.dispose);
      final timer = container.read(restTimerProvider.notifier);
      RestTimerState state() => container.read(restTimerProvider)!;

      timer.start(const Duration(seconds: 60));
      await elapse(30);
      expect(state().remaining(now), const Duration(seconds: 30));

      timer.addTime();
      await elapse(35);
      expect(state().finished, isFalse);
      expect(buzzes, isEmpty);

      await elapse(6);
      expect(state().finished, isTrue);
      expect(buzzes, [kRestOverVibration]);
      expect(kRestOverVibration, const Duration(seconds: 3));

      // "Not ready yet" after it rang: a fresh 10 seconds.
      timer.addTime();
      expect(state().finished, isFalse);
      expect(state().remaining(now), const Duration(seconds: 10));
      await elapse(11);
      expect(buzzes, hasLength(2));

      timer.dismiss();
      expect(container.read(restTimerProvider), isNull);
    });

    test('formats as m:ss', () {
      expect(formatRest(const Duration(seconds: 90)), '1:30');
      expect(formatRest(const Duration(seconds: 5)), '0:05');
    });
  });
}
