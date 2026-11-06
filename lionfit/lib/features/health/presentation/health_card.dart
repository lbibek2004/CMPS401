import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../home/presentation/home_section.dart';
import '../application/health_controller.dart';
import '../domain/health_models.dart';

/// "Today's activity" on Home: steps and heart rate from Health Connect.
///
/// Renders nothing where Health Connect does not exist (web, iOS, old
/// Android), so callers can place it unconditionally. When it does render it
/// brings its own top spacing.
class HealthCard extends ConsumerStatefulWidget {
  const HealthCard({super.key});

  @override
  ConsumerState<HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends ConsumerState<HealthCard> {
  late final AppLifecycleListener _lifecycle;

  /// True after sending the user to Health Connect or the Play Store, so
  /// coming back re-reads at once - their access may have just changed.
  bool _awayInHealthConnect = false;
  bool _busy = false;

  HealthController get _controller => ref.read(healthProvider.notifier);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    if (_awayInHealthConnect) {
      _awayInHealthConnect = false;
      _controller.refresh();
    } else {
      _controller.refreshIfStale();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    _awayInHealthConnect = true;
    final opened = await _controller.openSettings();
    if (opened || !mounted) return;
    _awayInHealthConnect = false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open Health Connect.')),
    );
  }

  Future<void> _install() async {
    _awayInHealthConnect = true;
    await _controller.install();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(healthProvider);
    final Widget? body = switch (status) {
      AsyncValue(value: final HealthStatus value) => switch (value) {
        HealthUnsupported() => null,
        HealthNeedsInstall() => _Invite(
          message:
              'See your steps and heart rate here. LionFit reads them from '
              'Health Connect, where Fitbit, Samsung Health and your phone '
              'store them. Health Connect is missing or out of date on this '
              'phone.',
          actionLabel: 'Get Health Connect',
          onAction: _busy ? null : () => _run(_install),
        ),
        HealthNeedsAccess(:final declined) => _Invite(
          message: declined
              ? 'Nothing was shared. To change that, turn on LionFit in '
                    "Health Connect's app permissions."
              : 'See your steps and heart rate here. LionFit reads them '
                    'from Health Connect (Fitbit, Samsung Health, your '
                    'phone) - read-only, and kept on this phone.',
          actionLabel: declined ? 'Open Health Connect' : 'Connect',
          onAction: _busy
              ? null
              : () => _run(declined ? _openSettings : _controller.connect),
        ),
        HealthReady(:final today) => _Today(today: today),
      },
      AsyncError() => SectionStatus.error(
        message: 'Could not read Health Connect.',
        onRetry: _controller.refresh,
      ),
      // First check: brief, and on web it ends in "unsupported" - so show
      // nothing rather than a loader that then vanishes.
      _ => null,
    };
    if (body == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: HomeSection(
        title: "Today's activity",
        subtitle: 'From Health Connect',
        action: _Menu(
          connected: status.value is HealthReady,
          // Nothing to open until Health Connect is installed.
          installed: status.value is! HealthNeedsInstall,
          onRefresh: () => _run(_controller.refresh),
          onManage: _openSettings,
        ),
        child: AnimatedOpacity(
          opacity: _busy ? 0.6 : 1,
          duration: const Duration(milliseconds: 150),
          child: body,
        ),
      ),
    );
  }
}

enum _MenuAction { refresh, manage, about }

class _Menu extends StatelessWidget {
  const _Menu({
    required this.connected,
    required this.installed,
    required this.onRefresh,
    required this.onManage,
  });

  final bool connected;
  final bool installed;
  final VoidCallback onRefresh;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Health Connect options',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => switch (action) {
        _MenuAction.refresh => onRefresh(),
        _MenuAction.manage => onManage(),
        _MenuAction.about => context.push(Routes.healthPrivacy),
      },
      itemBuilder: (_) => [
        if (connected)
          const PopupMenuItem(
            value: _MenuAction.refresh,
            child: ListTile(
              leading: Icon(Icons.refresh),
              title: Text('Refresh'),
            ),
          ),
        if (installed)
          const PopupMenuItem(
            value: _MenuAction.manage,
            child: ListTile(
              leading: Icon(Icons.tune),
              title: Text('Manage access'),
            ),
          ),
        const PopupMenuItem(
          value: _MenuAction.about,
          child: ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('How LionFit uses this data'),
          ),
        ),
      ],
    );
  }
}

/// Not connected yet: one sentence and one button.
class _Invite extends StatelessWidget {
  const _Invite({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

/// Connected: three tiles and when they were read.
class _Today extends StatelessWidget {
  const _Today({required this.today});

  final DailyHealth today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime at) =>
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(at));

    final heartRate = today.heartRate;
    final resting = today.restingHeartRate;
    final tiles = [
      _Tile(
        icon: Icons.directions_walk,
        label: 'Steps today',
        value: today.steps == null ? null : groupThousands(today.steps!),
        detail: _detailFor(today, HealthMetric.steps, hasValue: true),
      ),
      _Tile(
        icon: Icons.favorite_border,
        label: 'Avg heart rate',
        value: heartRate == null ? null : '${heartRate.average}',
        unit: 'bpm',
        detail:
            _detailFor(
              today,
              HealthMetric.heartRate,
              hasValue: heartRate != null,
            ) ??
            '${heartRate!.min}-${heartRate.max} today',
      ),
      _Tile(
        icon: Icons.bedtime_outlined,
        label: 'Resting heart rate',
        value: resting == null ? null : '${resting.bpm}',
        unit: 'bpm',
        detail:
            _detailFor(
              today,
              HealthMetric.restingHeartRate,
              hasValue: resting != null,
            ) ??
            relativeDayLabel(resting!.at, today.day, localizations),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Three across on a phone; one per row when large text would
            // squeeze them.
            const spacing = 12.0;
            final minTile = 104 * MediaQuery.textScalerOf(context).scale(1);
            final columns =
                ((constraints.maxWidth + spacing) / (minTile + spacing))
                    .floor()
                    .clamp(1, 3);
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final tile in tiles) SizedBox(width: width, child: tile),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Updated ${time(today.updatedAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// "Not shared" / "No readings yet" when there is no value to describe,
  /// otherwise null so the caller supplies the detail line.
  static String? _detailFor(
    DailyHealth today,
    HealthMetric metric, {
    required bool hasValue,
  }) {
    if (!today.isShared(metric)) return 'Not shared';
    if (!hasValue) return 'No readings yet';
    return null;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.detail,
  });

  final IconData icon;
  final String label;

  /// Null shows a dash.
  final String? value;
  final String? unit;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final spoken = [
      label,
      value == null ? 'no value' : '$value ${unit ?? ''}'.trim(),
      ?detail,
    ].join(', ');

    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value ?? '-',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (value != null && unit != null)
                    TextSpan(text: ' $unit', style: muted),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelMedium),
            if (detail != null) Text(detail!, style: muted),
          ],
        ),
      ),
    );
  }
}

/// 6214 -> "6,214".
String groupThousands(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// "Today", "Yesterday", or a short date for an older reading.
String relativeDayLabel(
  DateTime at,
  DateTime today,
  MaterialLocalizations localizations,
) {
  // UTC dates, so a daylight-saving change (a 23- or 25-hour day) does not
  // shift the count.
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => localizations.formatShortMonthDay(at),
  };
}
