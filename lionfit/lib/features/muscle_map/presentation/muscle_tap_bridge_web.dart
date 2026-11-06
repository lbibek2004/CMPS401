import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'muscle_tap_js.dart';

const _callbackName = 'lionfitMuscleTap';

/// Web: model_viewer_plus writes its markup with `innerHTML`, so a script in
/// `relatedJs` never runs here. Instead this appends one `<script>` to the
/// page and exposes [onTap] as a global function for it to call.
///
/// Returns a function that detaches [onTap]; the listener itself stays (it is
/// inert with no callback set, and installing it twice is guarded).
void Function() installWebMuscleTap(void Function(String material) onTap) {
  globalContext.setProperty(
    _callbackName.toJS,
    ((JSString name) => onTap(name.toDart)).toJS,
  );
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final script = document.callMethod<JSObject>(
    'createElement'.toJS,
    'script'.toJS,
  );
  script.setProperty(
    'text'.toJS,
    muscleTapScript('window.$_callbackName && window.$_callbackName').toJS,
  );
  document
      .getProperty<JSObject>('head'.toJS)
      .callMethod<JSAny?>('appendChild'.toJS, script);
  return () => globalContext.delete(_callbackName.toJS);
}
