import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../../core/training/muscle_labels.dart';
import '../../../core/training/muscle_status.dart';
import '../../coach/data/coach_providers.dart';
import '../../coach/domain/muscle_insight.dart';
import '../../home/presentation/plan_section.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/workout_models.dart';
import 'muscle_map_screen.dart';

/// Slides up when a muscle is tapped - on the 3D model or in the list.
Future<void> showMuscleDetailSheet(
  BuildContext context, {
  required MuscleStatusEntry entry,
  required int windowDays,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    minChildSize: 0.35,
    maxChildSize: 0.95,
    builder: (context, controller) => MuscleDetailSheet(
      entry: entry,
      windowDays: windowDays,
      scrollController: controller,
    ),
  ),
);

class MuscleDetailSheet extends ConsumerWidget {
  const MuscleDetailSheet({
    super.key,
    required this.entry,
    required this.windowDays,
    this.scrollController,
  });

  final MuscleStatusEntry entry;
  final int windowDays;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = LionFitTokens.of(context);
    final group = entry.group;
    final records = ref.watch(recentSetsProvider).value ?? const [];
    final catalog = ref.watch(exerciseCatalogProvider).value ?? const [];
    final engine = ref.watch(coachEngineProvider).value;
    final insights = ref.watch(coachInsightsProvider).value;
    final today = calendarDay(DateTime.now());
    final since = today.subtract(Duration(days: windowDays - 1));

    final insight = muscleInsight(
      group: group,
      sets: records.where((s) => !s.performedOn.isBefore(since)),
      exercisesById: {for (final e in catalog) e.id: e},
      windowDays: windowDays,
    );
    final needsWork = entry.status != MuscleTrainingStatus.wellTrained;
    final aiPick = insights?.muscleGapTips[group.wireName];
    final suggestions = needsWork && engine != null
        ? [
            for (final e in engine.candidatesFor(group, limit: 3))
              engine.suggestFor(e),
          ]
        : const [];
    final sets = formatTrimmed((entry.hardSets * 10).round() / 10);
    final target = formatTrimmed((entry.target * 10).round() / 10);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: statusColor(tokens, entry.status),
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outline),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                muscleGroupLabel(group),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(entry.status.label, style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$sets of $target hard sets in the last $windowDays '
          '${windowDays == 1 ? 'day' : 'days'}. ${insight.headline}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'What trained it',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (insight.isEmpty)
          Text(
            'Nothing yet in this window.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (final c in insight.contributions) _ContributionRow(c: c),
        if (needsWork) ...[
          const SizedBox(height: 24),
          Text(
            'Suggested to catch up',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Weights come from your history, rounded to what the machine '
            'can be set to. You can change them before logging.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (engine == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (suggestions.isEmpty)
            const Text('No available equipment trains this directly today.')
          else
            for (final s in suggestions)
              PlannedExerciseRow(
                suggestion: s,
                tip: aiPick != null && aiPick.exerciseSlug == s.exercise.slug
                    ? aiPick.tip
                    : s.reason,
              ),
        ],
      ],
    );
  }
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({required this.c});

  final ExerciseContribution c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (roleLabel, roleHelp) = switch (c.role) {
      MuscleRole.direct => (
        'Direct',
        'This muscle is what the exercise targets.',
      ),
      MuscleRole.assisted => (
        'Assisted',
        'Worked as a helper while another muscle did the main job. Counts as half a set.',
      ),
      MuscleRole.viaUnmapped => (
        'Via ${unmappedRegionLabel(c.unmappedRegion!).toLowerCase()}',
        'The real target has no 3D shape on the model, so it is drawn here. '
            'Counts as half a set.',
      ),
    };
    final best = c.bestSet;
    final parts = <String>[
      if (best != null) 'best ${describeSet(best)}',
      '${c.workingSets} ${c.workingSets == 1 ? 'set' : 'sets'}'
          '${c.sessions > 1 ? ' over ${c.sessions} days' : ''}',
      '${c.totalReps} reps',
    ];
    final trend = c.trend;
    final trendText = trend == null
        ? null
        : trend.abs() < 0.01
        ? 'Strength about level across the window.'
        : 'Estimated 1RM ${trend > 0 ? 'up' : 'down'} '
              '${(trend.abs() * 100).toStringAsFixed(0)}% across the window.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: roleHelp,
            child: Container(
              width: 92,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.role == MuscleRole.direct
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                roleLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: c.role == MuscleRole.direct
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.exercise.name, style: theme.textTheme.bodyLarge),
                Text(
                  parts.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (trendText != null)
                  Text(trendText, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
