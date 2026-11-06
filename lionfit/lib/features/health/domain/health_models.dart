/// Health data LionFit reads from Health Connect on Android, and the pure
/// functions that turn raw readings into what the Home card shows.
///
/// Nothing here talks to a platform API, so all of it is unit-tested.
library;

/// The three metrics LionFit asks for. Kept deliberately small: Health
/// Connect permissions are per data type, and every extra one is another
/// line on a consent screen the user has to trust.
enum HealthMetric {
  steps('Steps'),
  heartRate('Heart rate'),
  restingHeartRate('Resting heart rate');

  const HealthMetric(this.label);

  final String label;
}

/// One heart-rate value at a moment, in beats per minute.
class HeartRateReading {
  const HeartRateReading({required this.at, required this.bpm});

  final DateTime at;
  final int bpm;
}

/// Readings outside this range are sensor noise (a strap that slipped, a
/// manual entry typo), not physiology. Same bounds as the
/// `user_health_metrics` check constraints.
const kMinPlausibleBpm = 25;
const kMaxPlausibleBpm = 250;

bool isPlausibleBpm(num bpm) =>
    bpm >= kMinPlausibleBpm && bpm <= kMaxPlausibleBpm;

/// Today's heart rate at a glance.
class HeartRateSummary {
  const HeartRateSummary({
    required this.average,
    required this.min,
    required this.max,
    required this.latest,
    required this.readings,
  });

  final int average;
  final int min;
  final int max;
  final HeartRateReading latest;

  /// How many readings the summary is built from.
  final int readings;
}

/// Average / range / latest over [readings], or null when there is nothing
/// plausible to summarise.
HeartRateSummary? summarizeHeartRate(Iterable<HeartRateReading> readings) {
  final valid = [
    for (final r in readings)
      if (isPlausibleBpm(r.bpm)) r,
  ];
  if (valid.isEmpty) return null;
  var sum = 0;
  var min = valid.first.bpm;
  var max = valid.first.bpm;
  var latest = valid.first;
  for (final r in valid) {
    sum += r.bpm;
    if (r.bpm < min) min = r.bpm;
    if (r.bpm > max) max = r.bpm;
    if (r.at.isAfter(latest.at)) latest = r;
  }
  return HeartRateSummary(
    average: (sum / valid.length).round(),
    min: min,
    max: max,
    latest: latest,
    readings: valid.length,
  );
}

/// The most recent plausible reading, or null.
HeartRateReading? latestReading(Iterable<HeartRateReading> readings) {
  HeartRateReading? latest;
  for (final r in readings) {
    if (!isPlausibleBpm(r.bpm)) continue;
    if (latest == null || r.at.isAfter(latest.at)) latest = r;
  }
  return latest;
}

/// What the Home card shows for one day.
///
/// A metric the user did not share is null *and* absent from [shared], so
/// the card can tell "not shared" apart from "shared, but nothing recorded".
class DailyHealth {
  const DailyHealth({
    required this.day,
    required this.shared,
    required this.updatedAt,
    this.steps,
    this.heartRate,
    this.restingHeartRate,
  });

  /// Local calendar day the values cover.
  final DateTime day;
  final Set<HealthMetric> shared;
  final DateTime updatedAt;

  /// Steps since local midnight. Health Connect's aggregate, so a phone and a
  /// watch counting the same walk are not added together.
  final int? steps;

  /// Today's readings, summarised.
  final HeartRateSummary? heartRate;

  /// Watches compute resting heart rate once a day (often overnight), so this
  /// is the latest within the last week rather than strictly today's.
  final HeartRateReading? restingHeartRate;

  bool isShared(HealthMetric metric) => shared.contains(metric);
}

/// Where Health Connect stands on this device, from the app's point of view.
sealed class HealthStatus {
  const HealthStatus();
}

/// Not an Android phone, or one too old for Health Connect. The card hides.
final class HealthUnsupported extends HealthStatus {
  const HealthUnsupported();
}

/// Health Connect is missing or out of date. Android reports both with the
/// same status, so the app cannot tell them apart. Android 14+ has it built
/// in; older phones get it from the Play Store.
final class HealthNeedsInstall extends HealthStatus {
  const HealthNeedsInstall();
}

/// Health Connect is ready but LionFit has no read access yet.
///
/// [declined] is true right after the user said no. Android stops showing
/// the permission sheet after repeated refusals, so from then on the only
/// way back in is Health Connect's own settings.
final class HealthNeedsAccess extends HealthStatus {
  const HealthNeedsAccess({this.declined = false});

  final bool declined;
}

/// At least one metric is shared; [today] holds what was read.
final class HealthReady extends HealthStatus {
  const HealthReady(this.today);

  final DailyHealth today;
}
