/// Where health readings come from.
///
/// On Android that is **Health Connect**, the phone's shared health store:
/// the Google Health (Fitbit) app, Samsung Health, the phone's own step
/// counter and others write into it, and LionFit reads from it with the
/// user's permission. Nothing is fetched from a cloud API, and LionFit keeps
/// what it reads on the device - it is shown, not uploaded.
///
/// The web build gets a stub that reports [HealthAvailability.unsupported],
/// so the `health` plugin (which needs `dart:io`) is never compiled for web.
library;

import '../domain/health_models.dart';
import 'health_source_unsupported.dart'
    if (dart.library.io) 'health_connect_source.dart'
    as platform;

enum HealthAvailability {
  /// No Health Connect on this platform (web, iOS, desktop, Android < 9).
  unsupported,

  /// The Health Connect app is missing or out of date (Android 13 and older,
  /// where it is a Play Store app). Android does not say which.
  needsInstall,
  available,
}

abstract interface class HealthSource {
  Future<HealthAvailability> availability();

  /// Opens the Play Store page for Health Connect.
  Future<void> openInstall();

  /// Opens Health Connect's own settings, where the user can grant or revoke
  /// LionFit's access. Returns false if it could not be opened.
  Future<bool> openSettings();

  /// The metrics LionFit can currently read. Never prompts.
  Future<Set<HealthMetric>> sharedMetrics();

  /// Shows Health Connect's permission sheet for [metrics] and returns what
  /// is shared afterwards - the user may allow some and refuse others.
  Future<Set<HealthMetric>> requestAccess(Set<HealthMetric> metrics);

  /// Steps between [start] and [end], de-duplicated across sources by Health
  /// Connect. Null when nothing was recorded.
  Future<int?> steps(DateTime start, DateTime end);

  Future<List<HeartRateReading>> heartRate(DateTime start, DateTime end);

  Future<List<HeartRateReading>> restingHeartRate(DateTime start, DateTime end);
}

/// The source for the platform this build runs on.
HealthSource createHealthSource() => platform.createPlatformHealthSource();
