import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../../core/training/muscle_labels.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/workout_models.dart';
import '../../workout/presentation/log_workout_screen.dart';
import '../domain/history_filter.dart';

class HistoryFilterController extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();

  void setRange(HistoryRange range) => state = state.withRange(range);

  void setMuscle(MuscleGroup? muscle) => state = state.withMuscle(muscle);
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterController, HistoryFilter>(
      HistoryFilterController.new,
    );

/// `/history` - past workouts.
///
/// Opens on the last 7 days. Inside a week, a slider narrows it to 1-7 days;
/// the dropdown switches to whole calendar weeks going back a month. Muscle
/// chips filter both, and include exercises where the muscle only assisted.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final history = ref.watch(trainingHistoryProvider);
    final catalog = ref.watch(exerciseCatalogProvider);
    final today = calendarDay(DateTime.now());

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: HistoryControls(filter: filter, asOf: today),
                ),
              ),
              switch ((history, catalog)) {
                (AsyncError(), _) || (_, AsyncError()) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load your history.'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () {
                            ref.invalidate(trainingHistoryProvider);
                            ref.invalidate(exerciseCatalogProvider);
                          },
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
                (AsyncData(value: final sets), AsyncData(value: final c)) =>
                  _HistoryList(
                    days: applyHistoryFilter(
                      sets: sets,
                      exercisesById: {for (final e in c) e.id: e},
                      filter: filter,
                      asOf: today,
                    ),
                    filter: filter,
                    asOf: today,
                  ),
                _ => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Range dropdown, the within-week slider, and the muscle chips.
class HistoryControls extends ConsumerWidget {
  const HistoryControls({super.key, required this.filter, required this.asOf});

  final HistoryFilter filter;
  final DateTime asOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(historyFilterProvider.notifier);
    final range = filter.range;
    // The dropdown's first entry stands for "the slider"; picking it keeps
    // whatever day count the slider was on.
    final dropdownValue = switch (range) {
      RecentDays() => -1,
      CalendarWeek(:final weeksAgo) => weeksAgo,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          initialValue: dropdownValue,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Show'),
          items: [
            const DropdownMenuItem(
              value: -1,
              child: Text('Within the last week'),
            ),
            for (var w = 0; w <= kHistoryWeeksBack; w++)
              DropdownMenuItem(
                value: w,
                child: Text(CalendarWeek(w).label(asOf)),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            controller.setRange(
              value < 0
                  ? const RecentDays(kMaxRecentDays)
                  : CalendarWeek(value),
            );
          },
        ),
        if (range is RecentDays) ...[
          const SizedBox(height: 12),
          Text(
            range.label(asOf),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Slider(
            min: 1,
            max: kMaxRecentDays.toDouble(),
            divisions: kMaxRecentDays - 1,
            value: range.days.toDouble(),
            label: range.label(asOf),
            onChanged: (value) =>
                controller.setRange(RecentDays(value.round())),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('All muscles'),
                  selected: filter.muscle == null,
                  onSelected: (_) => controller.setMuscle(null),
                ),
              ),
              for (final group in MuscleGroup.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(muscleGroupLabel(group)),
                    selected: filter.muscle == group,
                    onSelected: (_) => controller.setMuscle(
                      filter.muscle == group ? null : group,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.days,
    required this.filter,
    required this.asOf,
  });

  final List<HistoryDay> days;
  final HistoryFilter filter;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (days.isEmpty) {
      final muscle = filter.muscle;
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            muscle == null
                ? 'Nothing logged ${filter.range.label(asOf).toLowerCase()}.'
                : 'No ${muscleGroupLabel(muscle).toLowerCase()} work '
                      '${filter.range.label(asOf).toLowerCase()}.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final totalSets = days.fold(0, (sum, d) => sum + d.setCount);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.list(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${days.length} ${days.length == 1 ? 'day' : 'days'} · '
              '$totalSets ${totalSets == 1 ? 'set' : 'sets'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final day in days) HistoryDayCard(day: day),
        ],
      ),
    );
  }
}

class HistoryDayCard extends StatelessWidget {
  const HistoryDayCard({super.key, required this.day});

  final HistoryDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Material, not a decorated Container: the expandable tiles below draw
    // their ink on the nearest Material.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            LionFitTokens.of(context).radiusLg,
          ),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                longDateLabel(day.day),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              for (final entry in day.entries)
                Theme(
                  // ExpansionTile draws dividers by default; the card has its own.
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: Text(entry.exercise.name),
                    subtitle: Text(
                      '${entry.sets.length} '
                      '${entry.sets.length == 1 ? 'set' : 'sets'} · '
                      'best ${describeSet(bestSetOf(entry.sets)!)}',
                    ),
                    children: [
                      for (final set in entry.sets)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SetIndexChip(set: set),
                              const SizedBox(width: 12),
                              Expanded(child: Text(describeSet(set))),
                              Text(
                                setTypeLabel(set.setType),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
