import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/health_source.dart';
import '../domain/health_models.dart';

/// The platform's health source. Tests override it with a fake.
final healthSourceProvider = Provider<HealthSource>(
  (ref) => createHealthSource(),
);

/// "Now", injectable so tests can pin the day.
final healthClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Watches report resting heart rate about once a day, often overnight, so
/// "the latest resting value" looks back this far.
const kRestingHeartRateLookback = Duration(days: 7);

/// Coming back to the app re-reads at most this often. Health Connect
/// rate-limits reads, and steps do not change meaningfully faster than this.
const kHealthAutoRefreshInterval = Duration(minutes: 1);

/// Health Connect status plus today's readings, for the Home card.
///
/// Reads only while the app is open (foreground reads need no extra
/// permission), and keeps nothing: every value is re-read from Health
/// Connect, which stays the single source of truth.
class HealthController extends AsyncNotifier<HealthStatus> {
  HealthSource get _source => ref.read(healthSourceProvider);

  @override
  Future<HealthStatus> build() => _read();

  Future<HealthStatus> _read({bool declined = false}) async {
    switch (await _source.availability()) {
      case HealthAvailability.unsupported:
        return const HealthUnsupported();
      case HealthAvailability.needsInstall:
        return const HealthNeedsInstall();
      case HealthAvailability.available:
        break;
    }
    final shared = await _source.sharedMetrics();
    if (shared.isEmpty) return HealthNeedsAccess(declined: declined);
    return HealthReady(await _today(shared));
  }

  Future<DailyHealth> _today(Set<HealthMetric> shared) async {
    final now = ref.read(healthClockProvider)();
    final midnight = DateTime(now.year, now.month, now.day);
    bool has(HealthMetric m) => shared.contains(m);

    // In parallel, and awaited together: if one read fails, the others'
    // failures are still handled rather than left as uncaught errors.
    final (steps, heartRate, resting) = await (
      has(HealthMetric.steps)
          ? _source.steps(midnight, now)
          : Future<int?>.value(),
      has(HealthMetric.heartRate)
          ? _source.heartRate(midnight, now)
          : Future.value(const <HeartRateReading>[]),
      has(HealthMetric.restingHeartRate)
          ? _source.restingHeartRate(
              now.subtract(kRestingHeartRateLookback),
              now,
            )
          : Future.value(const <HeartRateReading>[]),
    ).wait;

    return DailyHealth(
      day: midnight,
      shared: shared,
      updatedAt: now,
      steps: steps,
      heartRate: summarizeHeartRate(heartRate),
      restingHeartRate: latestReading(resting),
    );
  }

  /// Re-reads everything. The card keeps showing the current values while it
  /// runs, and keeps them if the read fails.
  Future<void> refresh() async {
    try {
      final next = await _read();
      if (ref.mounted) state = AsyncData(next);
    } catch (error, stackTrace) {
      debugPrint('health refresh failed: $error');
      if (ref.mounted && !state.hasValue) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  /// [refresh], unless today's values were read under a minute ago. For
  /// "the app came back to the foreground".
  Future<void> refreshIfStale() async {
    if (state.value case HealthReady(:final today)) {
      final age = ref.read(healthClockProvider)().difference(today.updatedAt);
      if (age < kHealthAutoRefreshInterval) return;
    }
    await refresh();
  }

  /// Shows Health Connect's permission sheet for every metric. The user may
  /// allow all, some, or none.
  Future<void> connect() async {
    try {
      final granted = await _source.requestAccess(HealthMetric.values.toSet());
      final HealthStatus next = granted.isEmpty
          ? const HealthNeedsAccess(declined: true)
          : HealthReady(await _today(granted));
      if (ref.mounted) state = AsyncData(next);
    } catch (error) {
      debugPrint('health connect failed: $error');
      await refresh();
    }
  }

  Future<void> install() => _source.openInstall();

  /// Health Connect's own settings, where access is granted or revoked.
  Future<bool> openSettings() => _source.openSettings();
}

final healthProvider = AsyncNotifierProvider<HealthController, HealthStatus>(
  HealthController.new,
);
