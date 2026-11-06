/// Platform switch for the tap bridge: the web build installs a page-level
/// listener; everywhere else (Android WebView, tests) this is a no-op and the
/// WebView's JavaScript channel carries the tap instead.
library;

export 'muscle_tap_bridge_stub.dart'
    if (dart.library.js_interop) 'muscle_tap_bridge_web.dart';
