/// A long vibration (the rest timer's "time's up").
///
/// Flutter's [HapticFeedback] only does short taps, so each platform gets its
/// own path:
///
/// * **Android**: a `lionfit/vibration` method channel into `MainActivity.kt`,
///   which calls the system `Vibrator` (needs the `VIBRATE` permission in the
///   manifest).
/// * **Web**: `navigator.vibrate()`. Android Chrome honours it; desktop
///   browsers and iOS Safari ignore it silently.
///
/// Never throws - a phone that cannot vibrate just does not.
library;

export 'vibration_io.dart' if (dart.library.js_interop) 'vibration_web.dart';
