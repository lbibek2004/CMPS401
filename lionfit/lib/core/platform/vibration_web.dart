import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Vibrates for [duration] through `navigator.vibrate`. See `vibration.dart`.
Future<void> vibrateFor(Duration duration) async {
  try {
    final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
    if (navigator.has('vibrate')) {
      navigator.callMethod<JSAny?>(
        'vibrate'.toJS,
        duration.inMilliseconds.toJS,
      );
    }
  } catch (_) {
    // Not supported here; nothing to do.
  }
}
