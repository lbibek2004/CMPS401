import '../domain/health_models.dart';
import 'health_source.dart';

/// Web: there is no Health Connect in a browser.
HealthSource createPlatformHealthSource() => const UnsupportedHealthSource();

/// Reports "unsupported" and reads nothing. Also used on non-Android native
/// platforms by the Health Connect source.
class UnsupportedHealthSource implements HealthSource {
  const UnsupportedHealthSource();

  @override
  Future<HealthAvailability> availability() async =>
      HealthAvailability.unsupported;

  @override
  Future<void> openInstall() async {}

  @override
  Future<bool> openSettings() async => false;

  @override
  Future<Set<HealthMetric>> sharedMetrics() async => const {};

  @override
  Future<Set<HealthMetric>> requestAccess(Set<HealthMetric> metrics) async =>
      const {};

  @override
  Future<int?> steps(DateTime start, DateTime end) async => null;

  @override
  Future<List<HeartRateReading>> heartRate(
    DateTime start,
    DateTime end,
  ) async => const [];

  @override
  Future<List<HeartRateReading>> restingHeartRate(
    DateTime start,
    DateTime end,
  ) async => const [];
}
