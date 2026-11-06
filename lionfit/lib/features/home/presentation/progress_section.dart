import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/training/models.dart';
import '../../coach/domain/progress.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/domain/workout_models.dart';
import 'home_section.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _md(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// "Progress", inline on the home page: this week's activity, then a line of
/// the average working set per session for one exercise, compared with the
/// week before or with the personal best.
class ProgressSection extends ConsumerStatefulWidget {
  const ProgressSection({super.key});

  @override
  ConsumerState<ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends ConsumerState<ProgressSection> {
  String? _exerciseId;
  ProgressComparison _comparison = ProgressComparison.lastWeek;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(trainingHistoryProvider);
    final catalog = ref.watch(exerciseCatalogProvider).value ?? const [];
    final unit =
        (ref.watch(trainingProfileProvider).value ?? const TrainingProfile())
            .unit;
    final byId = {for (final e in catalog) e.id: e};

    return HomeSection(
      title: 'Progress',
      subtitle: 'Average working set per session, last 12 weeks',
      child: history.when(
        skipLoadingOnReload: true,
        loading: () => const SectionStatus.loading(),
        error: (_, _) => SectionStatus.error(
          message: 'Could not load your history.',
          onRetry: () => ref.invalidate(trainingHistoryProvider),
        ),
        data: (sets) {
          final ids = [
            for (final id in exercisesByFrequency(sets))
              if (byId.containsKey(id)) id,
          ];
          final week = compareWeeks(sets, asOf: calendarDay(DateTime.now()));
          if (ids.isEmpty) {
            return Text(
              'Log a few sessions and your lifts will chart here.',
              style: Theme.of(context).textTheme.bodyLarge,
            );
          }
          final selected = ids.contains(_exerciseId) ? _exerciseId! : ids.first;
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WeekStats(comparison: week),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(selected),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Exercise'),
                items: [
                  for (final id in ids)
                    DropdownMenuItem(
                      value: id,
                      child: Text(
                        byId[id]!.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _exerciseId = id),
              ),
              const SizedBox(height: 12),
              Text('Compare', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in ProgressComparison.values)
                    ChoiceChip(
                      label: Text(c.label),
                      selected: _comparison == c,
                      onSelected: (_) => setState(() => _comparison = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _AverageChart(
                progress: averageProgress(selected, sets),
                comparison: _comparison,
                unit: unit,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WeekStats extends StatelessWidget {
  const _WeekStats({required this.comparison});

  final WeekComparison comparison;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final delta = c.thisWeekSets - c.lastWeekSets;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Stat(
          label: 'Sets this week',
          value: '${c.thisWeekSets}',
          note: c.lastWeekSets == 0 && c.thisWeekSets == 0
              ? null
              : delta == 0
              ? 'same as last week'
              : '${delta > 0 ? '+' : ''}$delta vs last week',
        ),
        _Stat(label: 'Days trained', value: '${c.thisWeekDays}'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _AverageChart extends StatelessWidget {
  const _AverageChart({
    required this.progress,
    required this.comparison,
    required this.unit,
  });

  final AverageProgress progress;
  final ProgressComparison comparison;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points = progress.points;
    final loaded = progress.isLoaded;
    final suffix = loaded ? unit.wireName : 'reps';
    double y(double v) => loaded ? unit.fromLb(v) : v;
    String fmt(double v) =>
        '${formatTrimmed(roundToIncrement(y(v), 0.5))} $suffix';

    if (points.isEmpty) {
      return Text(
        'No working sets logged for this one yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    final latest = progress.latest!;
    final best = progress.best!;
    final change = progress.changeVs(comparison);
    final base = comparison == ProgressComparison.lastWeek
        ? progress.previousWeek.last
        : best.value;
    final isNewBest =
        comparison == ProgressComparison.personalBest &&
        points.length > 1 &&
        identical(best, latest) &&
        progress.runningBest[points.length - 2] < latest.value;

    final headline = _Headline(
      latest: 'Latest (${_md(latest.day)}): ${fmt(latest.value)}',
      against: switch (comparison) {
        ProgressComparison.lastWeek =>
          base == null
              ? 'Nothing logged the week before to compare.'
              : 'Week before: ${fmt(base)} average',
        ProgressComparison.personalBest =>
          isNewBest
              ? 'New personal best'
              : 'Best: ${fmt(best.value)} on ${_md(best.day)}',
      },
      change: change,
      highlight: isNewBest,
    );

    if (points.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headline,
          const SizedBox(height: 8),
          Text(
            'One session so far. The line starts with the second.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final first = points.first.day;
    double x(DateTime d) => DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(first.year, first.month, first.day))
        .inDays
        .toDouble();
    final main = [for (final p in points) FlSpot(x(p.day), y(p.value))];
    final compare = switch (comparison) {
      ProgressComparison.lastWeek => [
        for (var i = 0; i < points.length; i++)
          if (progress.previousWeek[i] case final v?)
            FlSpot(x(points[i].day), y(v)),
      ],
      ProgressComparison.personalBest => [
        for (var i = 0; i < points.length; i++)
          FlSpot(x(points[i].day), y(progress.runningBest[i])),
      ],
    };
    final ys = [...main, ...compare].map((s) => s.y);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.2).clamp(2, double.infinity).toDouble();
    final compareColor = scheme.secondary;
    final compareLabel = comparison == ProgressComparison.lastWeek
        ? 'Week-before average'
        : 'Personal best so far';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        headline,
        const SizedBox(height: 16),
        Semantics(
          label:
              'Average working set for this exercise from '
              '${fmt(points.first.value)} on ${_md(first)} to '
              '${fmt(latest.value)} on ${_md(latest.day)}, '
              '${points.length} sessions.',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: (minY - pad).clamp(0, double.infinity).toDouble(),
                  maxY: maxY + pad,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: scheme.outlineVariant, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            value.round().toString(),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: main.last.x == 0 ? 1 : main.last.x,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            _md(first.add(Duration(days: value.round()))),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => scheme.inverseSurface,
                      getTooltipItems: (touched) => [
                        for (final t in touched)
                          LineTooltipItem(
                            t.barIndex == 0
                                ? '${_md(first.add(Duration(days: t.x.round())))}\n'
                                      'avg ${formatTrimmed(roundToIncrement(t.y, 0.5))} $suffix'
                                : '$compareLabel\n'
                                      '${formatTrimmed(roundToIncrement(t.y, 0.5))} $suffix',
                            TextStyle(color: scheme.onInverseSurface),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: main,
                      color: scheme.primary,
                      barWidth: 3,
                      dotData: FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 4,
                          color: scheme.secondary,
                          strokeWidth: 2,
                          strokeColor: scheme.primary,
                        ),
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                    if (compare.isNotEmpty)
                      LineChartBarData(
                        spots: compare,
                        color: compareColor,
                        barWidth: 2,
                        isStepLineChart:
                            comparison == ProgressComparison.personalBest,
                        dashArray: const [6, 4],
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _LegendItem(color: scheme.primary, label: 'Your average'),
            _LegendItem(color: compareColor, label: compareLabel, dashed: true),
          ],
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.latest,
    required this.against,
    required this.change,
    required this.highlight,
  });

  final String latest;
  final String against;
  final double? change;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = change;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                latest,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                against,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: highlight ? scheme.secondary : scheme.onSurfaceVariant,
                  fontWeight: highlight ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
        if (c != null && !highlight)
          Text(
            '${c >= 0 ? '+' : ''}${(c * 100).toStringAsFixed(1)}%',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: c >= 0 ? scheme.primary : scheme.error,
            ),
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 3,
          child: dashed
              ? Row(
                  children: [
                    Expanded(child: ColoredBox(color: color)),
                    const SizedBox(width: 3),
                    Expanded(child: ColoredBox(color: color)),
                    const SizedBox(width: 3),
                    Expanded(child: ColoredBox(color: color)),
                  ],
                )
              : ColoredBox(color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
