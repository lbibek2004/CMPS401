import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../../core/training/muscle_labels.dart';
import '../../../core/training/muscle_status.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/workout_models.dart';
import 'muscle_detail_sheet.dart';
import 'muscle_model_view.dart';

/// The user's chosen window. Null = the default ("longest with data").
class MapWindowController extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int days) => state = days;
}

final mapWindowProvider = NotifierProvider<MapWindowController, int?>(
  MapWindowController.new,
);

/// Everything the screen needs, derived from the catalog and the last 30 days
/// of sets.
final muscleStatusProvider = FutureProvider<MuscleStatusReport>((ref) async {
  final exercises = await ref.watch(exerciseCatalogProvider.future);
  final records = await ref.watch(recentSetsProvider.future);
  final sets = records.map((record) => record.toLoggedSet()).toList();
  final today = calendarDay(DateTime.now());
  final window =
      ref.watch(mapWindowProvider) ?? defaultMapWindowDays(sets, asOf: today);
  return muscleStatusReport(
    sets: sets,
    catalog: catalogOf(exercises),
    asOf: today,
    windowDays: window,
  );
});

Color statusColor(LionFitTokens tokens, MuscleTrainingStatus status) =>
    switch (status) {
      MuscleTrainingStatus.untrained => tokens.muscleUntrained,
      MuscleTrainingStatus.lessTrained => tokens.muscleLessTrained,
      MuscleTrainingStatus.wellTrained => tokens.muscleWellTrained,
    };

/// `/map` - the 3D muscle map: red untrained, yellow less trained, green
/// well trained, over a 1-30 day window.
class MuscleMapScreen extends ConsumerWidget {
  const MuscleMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(muscleStatusProvider);

    return Scaffold(
      body: report.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your training history.'),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  ref.invalidate(recentSetsProvider);
                  ref.invalidate(exerciseCatalogProvider);
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (report) => _MapLayout(report: report),
      ),
    );
  }
}

class _MapLayout extends StatelessWidget {
  const _MapLayout({required this.report});

  final MuscleStatusReport report;

  @override
  Widget build(BuildContext context) {
    final tokens = LionFitTokens.of(context);
    final colors = {
      for (final group in MuscleGroup.values)
        group: statusColor(tokens, report.statusOf(group)),
    };
    final summary =
        '3D muscle map, last ${report.windowDays} '
        '${report.windowDays == 1 ? 'day' : 'days'}: '
        '${report.countWith(MuscleTrainingStatus.wellTrained)} well trained, '
        '${report.countWith(MuscleTrainingStatus.lessTrained)} less trained, '
        '${report.countWith(MuscleTrainingStatus.untrained)} untrained.';

    void open(MuscleGroup group) => showMuscleDetailSheet(
      context,
      entry: report.byMuscleGroup[group]!,
      windowDays: report.windowDays,
    );

    final model = ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      child: MuscleModelView(
        colors: colors,
        semanticsLabel: summary,
        onMuscleTap: open,
      ),
    );
    final panel = _Panel(report: report, onOpen: open);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: model),
                const SizedBox(width: 24),
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(child: panel),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: (constraints.maxHeight * 0.6).clamp(320, 560),
                child: model,
              ),
              const SizedBox(height: 20),
              panel,
            ],
          ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.report, required this.onOpen});

  final MuscleStatusReport report;
  final ValueChanged<MuscleGroup> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = report.byMuscleGroup.values.toList()
      ..sort((a, b) {
        final byStatus = b.status.index.compareTo(a.status.index);
        return byStatus != 0 ? byStatus : b.hardSets.compareTo(a.hardSets);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WindowPicker(windowDays: report.windowDays),
        const SizedBox(height: 16),
        _Legend(report: report),
        const SizedBox(height: 8),
        Text(
          'Green means at least ${formatTrimmed(_oneDecimal(report.target))} '
          'hard sets in this window (10 a week, scaled; 3 minimum). '
          'Warm-ups do not count; assisting muscles count half.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a muscle on the model or in the list for what trained it '
          'and what to do next.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (!report.hasAnyTraining) ...[
          const SizedBox(height: 16),
          Text(
            'Nothing logged in this window yet - every muscle is red. Log a '
            'few sets and come back.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 16),
        Divider(height: 1, color: scheme.outlineVariant),
        const SizedBox(height: 8),
        for (final entry in entries)
          _MuscleRow(entry: entry, onTap: () => onOpen(entry.group)),
      ],
    );
  }

  static double _oneDecimal(double value) => (value * 10).round() / 10;
}

class _WindowPicker extends ConsumerStatefulWidget {
  const _WindowPicker({required this.windowDays});

  final int windowDays;

  @override
  ConsumerState<_WindowPicker> createState() => _WindowPickerState();
}

class _WindowPickerState extends ConsumerState<_WindowPicker> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = (_dragging ?? widget.windowDays.toDouble()).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last $shown ${shown == 1 ? 'day' : 'days'}',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Slider(
          min: kMinMapWindowDays.toDouble(),
          max: kMaxMapWindowDays.toDouble(),
          divisions: kMaxMapWindowDays - kMinMapWindowDays,
          value: _dragging ?? widget.windowDays.toDouble(),
          label: '$shown d',
          onChanged: (value) => setState(() => _dragging = value),
          // Commit on release: each commit rebuilds the 3D model.
          onChangeEnd: (value) {
            setState(() => _dragging = null);
            ref.read(mapWindowProvider.notifier).select(value.round());
          },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in const [1, 7, 14, 30])
              ChoiceChip(
                label: Text('$days d'),
                selected: widget.windowDays == days,
                onSelected: (_) =>
                    ref.read(mapWindowProvider.notifier).select(days),
              ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.report});

  final MuscleStatusReport report;

  @override
  Widget build(BuildContext context) {
    final tokens = LionFitTokens.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final status in MuscleTrainingStatus.values.reversed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(color: statusColor(tokens, status)),
              const SizedBox(width: 6),
              Flexible(
                child: Text('${status.label} (${report.countWith(status)})'),
              ),
            ],
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // The outline carries the 3:1 non-text contrast, so the fill does not
    // have to.
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

class _MuscleRow extends StatelessWidget {
  const _MuscleRow({required this.entry, required this.onTap});

  final MuscleStatusEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = LionFitTokens.of(context);
    final sets = formatTrimmed((entry.hardSets * 10).round() / 10);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            _Swatch(color: statusColor(tokens, entry.status)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                muscleGroupLabel(entry.group),
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                '$sets ${entry.hardSets == 1 ? 'set' : 'sets'} · ${entry.status.label}',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
