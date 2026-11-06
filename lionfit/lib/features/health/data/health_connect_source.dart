import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../domain/health_models.dart';
import 'health_source.dart';
import 'health_source_unsupported.dart';

/// Native builds: Health Connect on Android, nothing elsewhere.
HealthSource createPlatformHealthSource() => Platform.isAndroid
    ? HealthConnectSource()
    : const UnsupportedHealthSource();

/// Reads Health Connect through the `health` plugin.
///
/// Read-only by design: the manifest declares only `READ_*` permissions, so
/// LionFit cannot write to or delete anything in the user's health store.
class HealthConnectSource implements HealthSource {
  HealthConnectSource({Health? health}) : _health = health ?? Health();

  final Health _health;

  /// Opening Health Connect's settings is not in the plugin; MainActivity.kt
  /// handles it.
  static const _settingsChannel = MethodChannel('lionfit/health_connect');

  static const _types = {
    HealthMetric.steps: HealthDataType.STEPS,
    HealthMetric.heartRate: HealthDataType.HEART_RATE,
    HealthMetric.restingHeartRate: HealthDataType.RESTING_HEART_RATE,
  };

  Future<void>? _configured;

  /// The plugin must be configured once before any other call.
  Future<void> _ready() => _configured ??= _health.configure();

  @override
  Future<HealthAvailability> availability() async {
    await _ready();
    return switch (await _health.getHealthConnectSdkStatus()) {
      HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
        HealthAvailability.needsInstall,
      // sdkUnavailable (Android < 9), or the status query itself failed.
      _ => HealthAvailability.unsupported,
    };
  }

  @override
  Future<void> openInstall() => _health.installHealthConnect();

  @override
  Future<bool> openSettings() async {
    try {
      return await _settingsChannel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Set<HealthMetric>> sharedMetrics() async {
    await _ready();
    // One check per type: the user may share steps but not heart rate, and
    // the plugin's multi-type check only answers "all of them or not".
    return {
      for (final MapEntry(key: metric, value: type) in _types.entries)
        if (await _health.hasPermissions([type]) ?? false) metric,
    };
  }

  @override
  Future<Set<HealthMetric>> requestAccess(Set<HealthMetric> metrics) async {
    await _ready();
    final types = [for (final m in metrics) _types[m]!];
    // Its bool only says "something was granted"; re-check per type.
    await _health.requestAuthorization(
      types,
      permissions: [for (final _ in types) HealthDataAccess.READ],
    );
    return sharedMetrics();
  }

  @override
  Future<int?> steps(DateTime start, DateTime end) async {
    await _ready();
    return _health.getTotalStepsInInterval(start, end);
  }

  @override
  Future<List<HeartRateReading>> heartRate(DateTime start, DateTime end) =>
      _bpm(HealthDataType.HEART_RATE, start, end);

  @override
  Future<List<HeartRateReading>> restingHeartRate(
    DateTime start,
    DateTime end,
  ) => _bpm(HealthDataType.RESTING_HEART_RATE, start, end);

  Future<List<HeartRateReading>> _bpm(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    await _ready();
    final points = await _health.getHealthDataFromTypes(
      types: [type],
      startTime: start,
      endTime: end,
    );
    return [
      for (final p in points)
        if (p.value case NumericHealthValue(:final numericValue))
          HeartRateReading(at: p.dateFrom, bpm: numericValue.round()),
    ];
  }
}
