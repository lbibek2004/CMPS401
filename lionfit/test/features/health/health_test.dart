import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/router/app_router.dart';
import 'package:lionfit/core/theme/app_theme.dart';
import 'package:lionfit/features/health/application/health_controller.dart';
import 'package:lionfit/features/health/data/health_source.dart';
import 'package:lionfit/features/health/domain/health_models.dart';
import 'package:lionfit/features/health/presentation/health_card.dart';
import 'package:lionfit/features/health/presentation/health_privacy_screen.dart';
import 'package:lionfit/features/home/presentation/home_section.dart';

/// Health Connect as a scriptable fake: what is installed, what the user
/// shares, what they say yes to, and what each read returns.
class _FakeHealth implements HealthSource {
  HealthAvailability status = HealthAvailability.available;
  Set<HealthMetric> shared = {};

  /// What the permission sheet ends with when [requestAccess] is called.
  Set<HealthMetric> grantOnRequest = HealthMetric.values.toSet();

  int? stepsToday = 6214;
  List<HeartRateReading> heart = [];
  List<HeartRateReading> resting = [];
  Object? readError;

  int requests = 0;
  int settingsOpened = 0;
  int installs = 0;
  final reads = <String>[];

  @override
  Future<HealthAvailability> availability() async => status;

  @override
  Future<void> openInstall() async => installs++;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<Set<HealthMetric>> sharedMetrics() async => {...shared};

  @override
  Future<Set<HealthMetric>> requestAccess(Set<HealthMetric> metrics) async {
    requests++;
    shared = {...shared, ...grantOnRequest.intersection(metrics)};
    return {...shared};
  }

  void _read(String what, DateTime start, DateTime end) {
    if (readError case final error?) throw error;
    reads.add('$what $start -> $end');
  }

  @override
  Future<int?> steps(DateTime start, DateTime end) async {
    _read('steps', start, end);
    return stepsToday;
  }

  @override
  Future<List<HeartRateReading>> heartRate(DateTime start, DateTime end) async {
    _read('heart', start, end);
    return heart;
  }

  @override
  Future<List<HeartRateReading>> restingHeartRate(
    DateTime start,
    DateTime end,
  ) async {
    _read('resting', start, end);
    return resting;
  }
}

final _now = DateTime(2026, 11, 5, 14, 30);
DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 11, 5, hour, minute);
HeartRateReading _bpm(DateTime at, int bpm) =>
    HeartRateReading(at: at, bpm: bpm);

void main() {
  group('heart-rate math', () {
    test('average, range and latest; noise ignored', () {
      final summary = summarizeHeartRate([
        _bpm(_at(9), 60),
        _bpm(_at(12), 140),
        _bpm(_at(11), 80),
        _bpm(_at(13), 0), // a strap that slipped
        _bpm(_at(13, 5), 300), // and a typo
      ])!;
      expect(summary.average, 93); // (60 + 140 + 80) / 3 = 93.3
      expect(summary.min, 60);
      expect(summary.max, 140);
      expect(summary.latest.at, _at(12));
      expect(summary.readings, 3);
    });

    test('nothing plausible means no summary', () {
      expect(summarizeHeartRate(const []), isNull);
      expect(summarizeHeartRate([_bpm(_at(9), 12)]), isNull);
    });

    test('latest resting value wins, regardless of order', () {
      final latest = latestReading([
        _bpm(DateTime(2026, 11, 3), 58),
        _bpm(DateTime(2026, 11, 4), 61),
        _bpm(DateTime(2026, 11, 2), 55),
      ]);
      expect(latest!.bpm, 61);
      expect(latestReading(const []), isNull);
    });

    test('labels', () {
      expect(groupThousands(0), '0');
      expect(groupThousands(999), '999');
      expect(groupThousands(6214), '6,214');
      expect(groupThousands(1234567), '1,234,567');
      const l10n = DefaultMaterialLocalizations();
      final today = DateTime(2026, 11, 5);
      expect(relativeDayLabel(_at(7), today, l10n), 'Today');
      expect(
        relativeDayLabel(DateTime(2026, 11, 4, 23), today, l10n),
        'Yesterday',
      );
      expect(relativeDayLabel(DateTime(2026, 11, 1), today, l10n), 'Nov 1');
      // Across the 2026-11-01 daylight-saving change in the US.
      expect(
        relativeDayLabel(
          DateTime(2026, 10, 31, 23),
          DateTime(2026, 11, 1),
          l10n,
        ),
        'Yesterday',
      );
    });
  });

  group('HealthController', () {
    late _FakeHealth health;
    late ProviderContainer container;
    var now = _now;

    setUp(() {
      now = _now;
      health = _FakeHealth();
      container = ProviderContainer(
        overrides: [
          healthSourceProvider.overrideWithValue(health),
          healthClockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<HealthStatus> status() => container.read(healthProvider.future);
    HealthController controller() => container.read(healthProvider.notifier);

    test(
      'no Health Connect on this platform: unsupported, nothing read',
      () async {
        health.status = HealthAvailability.unsupported;
        expect(await status(), isA<HealthUnsupported>());
        expect(health.reads, isEmpty);
      },
    );

    test('missing or outdated Health Connect: offer the install', () async {
      health.status = HealthAvailability.needsInstall;
      expect(await status(), isA<HealthNeedsInstall>());
      await controller().install();
      expect(health.installs, 1);
    });

    test('installed, nothing shared: ask, and read nothing yet', () async {
      final s = await status();
      expect(s, isA<HealthNeedsAccess>());
      expect((s as HealthNeedsAccess).declined, isFalse);
      expect(health.reads, isEmpty);
    });

    test('connect: everything shared, today read from midnight', () async {
      health.heart = [_bpm(_at(9), 64), _bpm(_at(10), 80)];
      health.resting = [_bpm(DateTime(2026, 11, 4, 6), 57)];
      await status();
      await controller().connect();

      final today =
          (container.read(healthProvider).value! as HealthReady).today;
      expect(health.requests, 1);
      expect(today.shared, HealthMetric.values.toSet());
      expect(today.steps, 6214);
      expect(today.heartRate!.average, 72);
      expect(today.restingHeartRate!.bpm, 57);
      expect(today.updatedAt, _now);
      expect(
        health.reads,
        containsAll([
          'steps ${DateTime(2026, 11, 5)} -> $_now',
          'heart ${DateTime(2026, 11, 5)} -> $_now',
          // Resting is reported about once a day: look back a week.
          'resting ${_now.subtract(const Duration(days: 7))} -> $_now',
        ]),
      );
    });

    test('connect: the user says no to everything', () async {
      health.grantOnRequest = {};
      await status();
      await controller().connect();
      final s = container.read(healthProvider).value;
      expect(s, isA<HealthNeedsAccess>());
      expect((s as HealthNeedsAccess).declined, isTrue);
      expect(health.reads, isEmpty);
    });

    test('connect: steps only - heart rate is never read', () async {
      health.grantOnRequest = {HealthMetric.steps};
      await status();
      await controller().connect();
      final today =
          (container.read(healthProvider).value! as HealthReady).today;
      expect(today.steps, 6214);
      expect(today.isShared(HealthMetric.heartRate), isFalse);
      expect(today.heartRate, isNull);
      expect(health.reads, hasLength(1));
    });

    test('a failed refresh keeps the numbers already on screen', () async {
      health.shared = HealthMetric.values.toSet();
      await status();
      health.readError = StateError('rate limited');
      health.stepsToday = 9000;
      await controller().refresh();
      final today =
          (container.read(healthProvider).value! as HealthReady).today;
      expect(today.steps, 6214);
    });

    test('coming back to the app re-reads at most once a minute', () async {
      health.shared = {HealthMetric.steps};
      await status();
      expect(health.reads, hasLength(1));

      now = _now.add(const Duration(seconds: 30));
      await controller().refreshIfStale();
      expect(health.reads, hasLength(1));

      now = _now.add(const Duration(minutes: 2));
      health.stepsToday = 7000;
      await controller().refreshIfStale();
      expect(health.reads, hasLength(2));
      final today =
          (container.read(healthProvider).value! as HealthReady).today;
      expect(today.steps, 7000);
    });
  });

  group('Home card', () {
    late _FakeHealth health;

    Future<void> pumpCard(
      WidgetTester tester, {
      Size size = const Size(400, 900),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            healthSourceProvider.overrideWithValue(health),
            healthClockProvider.overrideWithValue(() => _now),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: HealthCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() => health = _FakeHealth());

    testWidgets('hidden where there is no Health Connect', (tester) async {
      health.status = HealthAvailability.unsupported;
      await pumpCard(tester);
      expect(find.byType(HomeSection), findsNothing);
    });

    testWidgets('Connect, then today\'s numbers', (tester) async {
      health.heart = [_bpm(_at(9), 64), _bpm(_at(10), 80)];
      health.resting = [_bpm(_at(6), 57)];
      await pumpCard(tester);
      expect(find.text("Today's activity"), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.textContaining('read-only'), findsOneWidget);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(health.requests, 1);
      expect(find.text('6,214'), findsOneWidget);
      expect(find.text('72 bpm'), findsOneWidget);
      expect(find.text('64-80 today'), findsOneWidget);
      expect(find.text('57 bpm'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Updated 2:30 PM'), findsOneWidget);
      // One spoken label per tile, value and all.
      expect(find.bySemanticsLabel('Steps today, 6,214'), findsOneWidget);
    });

    testWidgets('a metric that is not shared says so', (tester) async {
      health.shared = {HealthMetric.steps};
      await pumpCard(tester);
      expect(find.text('6,214'), findsOneWidget);
      expect(find.text('Not shared'), findsNWidgets(2));
    });

    testWidgets('shared but nothing recorded yet', (tester) async {
      health.shared = HealthMetric.values.toSet();
      await pumpCard(tester);
      expect(find.text('No readings yet'), findsNWidgets(2));
    });

    testWidgets('after a refusal, the way back is Health Connect settings', (
      tester,
    ) async {
      health.grantOnRequest = {};
      await pumpCard(tester);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing was shared'), findsOneWidget);
      await tester.tap(find.text('Open Health Connect'));
      await tester.pumpAndSettle();
      expect(health.settingsOpened, 1);
      // Android stops showing the sheet after refusals; do not loop on it.
      expect(health.requests, 1);
    });

    testWidgets('missing Health Connect offers the install', (tester) async {
      health.status = HealthAvailability.needsInstall;
      await pumpCard(tester);
      await tester.tap(find.text('Get Health Connect'));
      await tester.pumpAndSettle();
      expect(health.installs, 1);
    });

    testWidgets('large text: tiles stack instead of overflowing', (
      tester,
    ) async {
      health.shared = HealthMetric.values.toSet();
      health.heart = [_bpm(_at(9), 64)];
      await pumpCard(tester, size: const Size(360, 1400), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('6,214'), findsOneWidget);
    });
  });

  group('privacy page', () {
    test('open to everyone: signed out, signed in, survey owed', () {
      for (final (signedIn, owed) in [
        (false, false),
        (true, false),
        (true, true),
      ]) {
        expect(
          redirectFor(
            location: Routes.healthPrivacy,
            signedIn: signedIn,
            needsOnboarding: owed,
          ),
          isNull,
        );
      }
    });

    testWidgets('says what is read, and that it stays on the phone', (
      tester,
    ) async {
      final health = _FakeHealth()..status = HealthAvailability.unsupported;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [healthSourceProvider.overrideWithValue(health)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const HealthPrivacyScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('What LionFit reads'), findsOneWidget);
      expect(
        find.textContaining('Steps, heart rate, and resting'),
        findsOneWidget,
      );
      expect(find.textContaining('stays on this phone'), findsOneWidget);
      // Nothing to open where Health Connect does not exist.
      expect(find.text('Open Health Connect'), findsNothing);
    });
  });
}
