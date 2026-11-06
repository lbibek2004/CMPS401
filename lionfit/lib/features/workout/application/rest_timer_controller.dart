/// The rest between sets: state and controller. The widgets that show it
/// live in `presentation/rest_timer.dart`.
///
/// Started by [TodaySessionController.logSet] after **every** saved set, so
/// no logging path (the Log tab, the plan's Log sheet, the muscle map) can
/// skip it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/vibration.dart';

/// How long the phone buzzes when rest is over.
const kRestOverVibration = Duration(seconds: 3);

/// What "+10s" adds.
const kRestExtension = Duration(seconds: 10);

/// How long "Rest over" stays up before the bar clears itself.
const kRestOverLinger = Duration(seconds: 30);

/// The clock and the buzzer, injectable so tests do not wait in real time or
/// call into a platform channel.
final restClockProvider = Provider<DateTime Function()>((_) => DateTime.now);
final restVibrateProvider = Provider<Future<void> Function(Duration)>(
  (_) => vibrateFor,
);

@immutable
final class RestTimerState {
  const RestTimerState({
    required this.endsAt,
    required this.total,
    this.finished = false,
    this.expanded = true,
  });

  /// Wall-clock end, not a countdown: a phone that sleeps mid-rest still
  /// shows the right time when it wakes.
  final DateTime endsAt;

  /// The full rest, including any +10s - for the progress bar.
  final Duration total;
  final bool finished;

  /// Full screen (the Android app) rather than the slim bar. The ✕ on the
  /// full-screen view collapses it; the countdown keeps going in the bar.
  final bool expanded;

  RestTimerState copyWith({
    DateTime? endsAt,
    Duration? total,
    bool? finished,
    bool? expanded,
  }) => RestTimerState(
    endsAt: endsAt ?? this.endsAt,
    total: total ?? this.total,
    finished: finished ?? this.finished,
    expanded: expanded ?? this.expanded,
  );

  Duration remaining(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// The rest between sets. Started by the logger after every set; lives above
/// the tabs so it keeps running while the user looks at the plan or the map.
class RestTimerController extends Notifier<RestTimerState?> {
  Timer? _timer;

  DateTime _now() => ref.read(restClockProvider)();

  @override
  RestTimerState? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void start(Duration rest) {
    final now = _now();
    state = RestTimerState(endsAt: now.add(rest), total: rest);
    _schedule();
  }

  /// "+10s, not ready yet". After the timer has run out it starts a fresh
  /// 10 seconds rather than extending a finished one.
  void addTime([Duration extra = kRestExtension]) {
    final current = state;
    if (current == null) return;
    if (current.finished) {
      start(extra);
      state = state?.copyWith(expanded: current.expanded);
      return;
    }
    state = current.copyWith(
      endsAt: current.endsAt.add(extra),
      total: current.total + extra,
    );
    _schedule();
  }

  /// Shrinks the full-screen timer to the bar; the countdown continues.
  void collapse() {
    final current = state;
    if (current != null) state = current.copyWith(expanded: false);
  }

  /// Skip the rest, or dismiss "Rest over".
  void dismiss() {
    _timer?.cancel();
    state = null;
  }

  void _schedule() {
    _timer?.cancel();
    final current = state;
    if (current == null) return;
    _timer = Timer(current.remaining(_now()), _finish);
  }

  void _finish() {
    final current = state;
    if (current == null || current.finished) return;
    state = current.copyWith(finished: true);
    // Only buzz when the timer ran out just now - not when a sleeping phone
    // wakes long after the fact.
    if (_now().difference(current.endsAt) < const Duration(seconds: 5)) {
      unawaited(ref.read(restVibrateProvider)(kRestOverVibration));
    }
    _timer = Timer(kRestOverLinger, () {
      if (state?.finished ?? false) state = null;
    });
  }
}

final restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState?>(
      RestTimerController.new,
    );
