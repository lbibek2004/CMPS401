import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/training/muscle_labels.dart';
import '../../coach/data/coach_providers.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/workout_models.dart';
import 'home_section.dart';
import 'plan_section.dart';

/// "Next session": the engine's next load for each recent lift, with
/// Gemini's phrasing when the coach-insights function is available.
class CoachSection extends ConsumerWidget {
  const CoachSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brief = ref.watch(coachBriefProvider);
    final insights = ref.watch(coachInsightsProvider).value;
    // Lifts logged today: their suggestion is already "next time", so they
    // are marked done instead of offering to log them again.
    final today = calendarDay(DateTime.now());
    final doneToday = {
      for (final set in ref.watch(trainingHistoryProvider).value ?? const [])
        if (set.performedOn == today) set.exerciseId,
    };

    return HomeSection(
      title: 'Next session',
      subtitle: 'From your own logged sets',
      child: brief.when(
        skipLoadingOnReload: true,
        loading: () => const SectionStatus.loading(),
        error: (_, _) => SectionStatus.error(
          message: 'Could not work out your next loads.',
          onRetry: () => ref.invalidate(coachEngineProvider),
        ),
        data: (brief) {
          if (brief.nextLoads.isEmpty && brief.muscleGaps.isEmpty) {
            return Text(
              'Log a session and your next loads show up here.',
              style: theme.textTheme.bodyLarge,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (insights?.summary case final summary?) ...[
                _AiLabel(model: insights?.model),
                const SizedBox(height: 4),
                Text(summary, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 12),
              ],
              if (brief.nextLoads.isEmpty)
                Text(
                  'Nothing logged in the last two weeks yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                for (final s in brief.nextLoads)
                  PlannedExerciseRow(
                    suggestion: s,
                    doneToday: doneToday.contains(s.exercise.id),
                    tip: insights?.nextLoadTips[s.exercise.slug] ?? s.reason,
                  ),
              if (brief.muscleGaps.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Behind this week: '
                  '${brief.muscleGaps.map((g) => muscleGroupLabel(g.group)).join(', ')}. '
                  'Tap a muscle on the muscle map for options.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AiLabel extends StatelessWidget {
  const _AiLabel({this.model});

  final String? model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.secondary),
        const SizedBox(width: 6),
        Text(
          'AI summary${model == null ? '' : ' · $model'}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
