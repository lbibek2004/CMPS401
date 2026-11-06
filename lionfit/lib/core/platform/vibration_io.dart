import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('lionfit/vibration');

/// Vibrates for [duration]. See `vibration.dart`.
Future<void> vibrateFor(Duration duration) async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod<void>('vibrate', {
        'milliseconds': duration.inMilliseconds,
      });
    } else {
      await HapticFeedback.heavyImpact();
    }
  } catch (error) {
    debugPrint('vibration unavailable: $error');
  }
}
