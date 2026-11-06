import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/rest_timer_controller.dart';

export '../application/rest_timer_controller.dart';

String formatRest(Duration d) {
  final seconds = d.inSeconds;
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// The strip above the navigation bar while resting: time left, +10s, skip.
/// Renders nothing when no rest is running.
class RestTimerBar extends ConsumerStatefulWidget {
  const RestTimerBar({super.key, this.whenExpanded = false});

  /// Also show while the timer is full screen. The web has no full-screen
  /// view, so its bar always shows.
  final bool whenExpanded;

  @override
  ConsumerState<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends ConsumerState<RestTimerBar> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => mounted ? setState(() {}) : null,
      );
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rest = ref.watch(restTimerProvider);
    _syncTicker(rest != null && !rest.finished);
    if (rest == null || (rest.expanded && !widget.whenExpanded)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(restTimerProvider.notifier);
    final now = ref.read(restClockProvider)();
    final left = rest.remaining(now);
    final progress = rest.total.inMilliseconds == 0
        ? 1.0
        : 1 - left.inMilliseconds / rest.total.inMilliseconds;
    final done = rest.finished;
    final background = done
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHigh;
    final ink = done ? scheme.onSecondaryContainer : scheme.onSurface;

    return Material(
      color: background,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!done)
              LinearProgressIndicator(
                value: progress.clamp(0, 1).toDouble(),
                minHeight: 3,
                backgroundColor: Colors.transparent,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Icon(
                    done ? Icons.notifications_active : Icons.timer_outlined,
                    color: done ? scheme.onSecondaryContainer : scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      liveRegion: done,
                      child: Text(
                        done
                            ? 'Rest over - next set'
                            : 'Rest ${formatRest(left)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: controller.addTime,
                    style: TextButton.styleFrom(
                      foregroundColor: ink,
                      minimumSize: const Size(48, 44),
                    ),
                    child: const Text('+10s'),
                  ),
                  TextButton(
                    onPressed: controller.dismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: ink,
                      minimumSize: const Size(48, 44),
                    ),
                    child: Text(done ? 'Dismiss' : 'Skip'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}

/// The Android rest screen: the app blurred and dimmed 40% behind a large
/// countdown, with +10s, Skip, and an ✕ that shrinks it to the bar.
class RestTimerOverlay extends ConsumerStatefulWidget {
  const RestTimerOverlay({super.key});

  @override
  ConsumerState<RestTimerOverlay> createState() => _RestTimerOverlayState();
}

class _RestTimerOverlayState extends ConsumerState<RestTimerOverlay> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => mounted ? setState(() {}) : null,
      );
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rest = ref.watch(restTimerProvider);
    final visible = rest != null && rest.expanded;
    _syncTicker(visible && !rest.finished);
    if (!visible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(restTimerProvider.notifier);
    final left = rest.remaining(ref.read(restClockProvider)());
    final done = rest.finished;
    final progress = rest.total.inMilliseconds == 0
        ? 1.0
        : left.inMilliseconds / rest.total.inMilliseconds;

    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          // Material, not ColoredBox: the overlay sits above the Scaffold,
          // and text needs a Material ancestor for its default style.
          child: Material(
            color: scheme.surface.withValues(alpha: 0.4),
            child: SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton.filledTonal(
                        tooltip: 'Close rest timer',
                        onPressed: controller.collapse,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            done ? 'Rest over' : 'Rest',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: done ? scheme.secondary : scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: 240,
                            height: 240,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CircularProgressIndicator(
                                  value: done
                                      ? 1
                                      : progress.clamp(0, 1).toDouble(),
                                  strokeWidth: 10,
                                  color: done
                                      ? scheme.secondary
                                      : scheme.primary,
                                  backgroundColor: scheme.outlineVariant,
                                ),
                                Center(
                                  child: Semantics(
                                    liveRegion: done,
                                    child: Text(
                                      done ? 'Go' : formatRest(left),
                                      style: theme.textTheme.displayMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.tonal(
                                onPressed: controller.addTime,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(120, 52),
                                ),
                                child: const Text('+10s'),
                              ),
                              FilledButton(
                                onPressed: controller.dismiss,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(120, 52),
                                ),
                                child: Text(done ? 'Next set' : 'Skip rest'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
