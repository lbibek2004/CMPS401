import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/muscle_labels.dart';
import '../../coach/data/coach_providers.dart';
import '../../coach/domain/coach_engine.dart';
import '../../coach/domain/weekly_plan.dart';
import '../../coach/presentation/log_suggestion_sheet.dart';
import '../../profile/presentation/plan_settings_sheet.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/domain/workout_models.dart';
import 'home_section.dart';

const _dayLetters = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Working sets (warm-ups do not count toward the plan).
int workingSetCount(Iterable<SetRecord> sets) =>
    sets.where((set) => set.setType.countsAsVolume).length;

/// A plan item is done once its planned number of working sets is logged.
/// Cardio is one "set" of minutes.
bool isPlanItemDone(SuggestedSet s, Iterable<SetRecord> logged) =>
    workingSetCount(logged) >= (s.exercise.isCardio ? 1 : s.sets);

/// "This week's plan", inline on the home page: a Mon-Sun strip and every
/// exercise on the selected day, each with **Log** and **Replace**.
///
/// Logging uses the confirm-and-log sheet. Replacing offers the top three
/// alternatives for the same muscles (`CoachEngine.swapOptionsFor`) and
/// stores the pick (`user_plan_swaps`). Either way the row is then marked -
/// "Logged" with what was done, or "Replaces (original)" - and the rest of
/// the day stays as it was: the plan is stable within a week.
class PlanSection extends ConsumerStatefulWidget {
  const PlanSection({super.key});

  @override
  ConsumerState<PlanSection> createState() => _PlanSectionState();
}

class _PlanSectionState extends ConsumerState<PlanSection> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(weeklyPlanProvider);
    final profile =
        ref.watch(trainingProfileProvider).value ?? const TrainingProfile();
    final history = ref.watch(trainingHistoryProvider).value ?? const [];
    // Today's sets come from the live session, which updates the instant a
    // set is saved; the history reloads a moment later.
    final session = ref.watch(todaySessionProvider).value;
    final today = calendarDay(DateTime.now());
    final trainedDays = {for (final s in history) s.performedOn};

    return HomeSection(
      title: "This week's plan",
      subtitle: '${profile.daysPerWeek} days · ${profile.goal.label}',
      action: TextButton.icon(
        onPressed: () => showPlanSettingsSheet(context, profile),
        icon: const Icon(Icons.tune, size: 18),
        label: const Text('Change'),
      ),
      child: plan.when(
        skipLoadingOnReload: true,
        loading: () => const SectionStatus.loading(),
        error: (_, _) => SectionStatus.error(
          message: 'Could not build your plan.',
          onRetry: () => ref.invalidate(trainingHistoryProvider),
        ),
        data: (plan) {
          final selected = _selected ?? _defaultDay(plan, today);
          final day = plan.dayFor(selected) ?? plan.days.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (plan.isCalibration) ...[
                const _CalibrationNote(),
                const SizedBox(height: 16),
              ],
              _DayStrip(
                plan: plan,
                today: today,
                selected: selected,
                trainedDays: trainedDays,
                onSelect: (d) => setState(() => _selected = d),
              ),
              const SizedBox(height: 16),
              _DayDetail(
                day: day,
                today: today,
                trained: trainedDays.contains(day.date),
                setsThatDay: day.date == today && session != null
                    ? session.sets
                    : [
                        for (final s in history)
                          if (s.performedOn == day.date) s,
                      ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Today; or, on a rest day, the next training day this week.
  static DateTime _defaultDay(WeeklyPlan plan, DateTime today) {
    final todayPlan = plan.dayFor(today);
    if (todayPlan != null && !todayPlan.isRest) return today;
    for (final day in plan.days) {
      if (!day.isRest && day.date.isAfter(today)) return day.date;
    }
    return today;
  }
}

/// Shown for a user's first week: why everything looks light.
class _CalibrationNote extends StatelessWidget {
  const _CalibrationNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(LionFitTokens.of(context).radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.explore_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Calibration week. Shorter days, two easy sets each. Rate every '
              'set (RPE or RIR) - your next weights are worked out from how '
              'these feel.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.plan,
    required this.today,
    required this.selected,
    required this.trainedDays,
    required this.onSelect,
  });

  final WeeklyPlan plan;
  final DateTime today;
  final DateTime selected;
  final Set<DateTime> trainedDays;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = LionFitTokens.of(context);

    return Row(
      children: [
        for (final day in plan.days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Semantics(
                button: true,
                selected: day.date == selected,
                label:
                    '${_dayLetters[day.date.weekday - 1]} ${day.date.day}, '
                    '${day.kind?.label ?? 'rest'}'
                    '${trainedDays.contains(day.date) ? ', trained' : ''}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                  onTap: () => onSelect(day.date),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: day.date == selected
                          ? scheme.primary
                          : day.isRest
                          ? Colors.transparent
                          : scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(tokens.radiusSm),
                      border: Border.all(
                        color: day.date == today
                            ? scheme.secondary
                            : scheme.outlineVariant,
                        width: day.date == today ? 2 : 1,
                      ),
                    ),
                    child: ExcludeSemantics(
                      child: Column(
                        children: [
                          Text(
                            _dayLetters[day.date.weekday - 1],
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: day.date == selected
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${day.date.day}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: day.date == selected
                                  ? scheme.onPrimary
                                  : day.isRest
                                  ? scheme.onSurfaceVariant
                                  : scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Icon(
                            trainedDays.contains(day.date)
                                ? Icons.check_circle
                                : day.isRest
                                ? Icons.remove
                                : Icons.circle_outlined,
                            size: 14,
                            color: day.date == selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayDetail extends ConsumerWidget {
  const _DayDetail({
    required this.day,
    required this.today,
    required this.trained,
    required this.setsThatDay,
  });

  final PlanDay day;
  final DateTime today;
  final bool trained;

  /// Everything logged on [day], planned or not.
  final List<SetRecord> setsThatDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToday = day.date == today;
    final when = isToday ? 'Today' : _dayLetters[day.date.weekday - 1];

    if (day.isRest) {
      return Text(
        trained
            ? '$when is a rest day in your plan, and you trained anyway.'
            : '$when is a rest day. Walk, stretch, or take it easy.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final done = day.exercises
        .where(
          (s) => isPlanItemDone(s, [
            for (final set in setsThatDay)
              if (set.exerciseId == s.exercise.id) set,
          ]),
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '$when · ${day.kind!.label}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$done of ${day.exercises.length} done',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          day.muscleGroups.map(muscleGroupLabel).join(', '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final s in day.exercises)
          _PlanRow(
            day: day,
            suggestion: s,
            replaced: day.replacedFrom[s.exercise.id],
            logged: [
              for (final set in setsThatDay)
                if (set.exerciseId == s.exercise.id) set,
            ],
            canLog: isToday,
            canReplace: !day.date.isBefore(today),
          ),
        if (!isToday)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              day.date.isBefore(today)
                  ? 'This day has passed.'
                  : 'Logging opens on the day itself. You can swap '
                        'exercises now.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// One planned exercise: its prescription, Log and Replace - or, once done,
/// what was logged.
class _PlanRow extends ConsumerWidget {
  const _PlanRow({
    required this.day,
    required this.suggestion,
    required this.replaced,
    required this.logged,
    required this.canLog,
    required this.canReplace,
  });

  final PlanDay day;
  final SuggestedSet suggestion;

  /// What the plan had here before the user swapped, if they did.
  final CatalogExercise? replaced;
  final List<SetRecord> logged;
  final bool canLog;
  final bool canReplace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = suggestion;
    final working = workingSetCount(logged);
    final done = isPlanItemDone(s, logged);
    final started = logged.isNotEmpty;
    final best = started ? _bestOf(logged) : null;

    final status = <Widget>[
      if (replaced != null)
        _Tag(
          icon: Icons.swap_horiz,
          text: 'Replaces ${replaced!.name}',
          emphasis: false,
        ),
      if (done)
        _Tag(
          icon: Icons.check,
          text:
              'Logged · ${logged.length} '
              '${logged.length == 1 ? 'set' : 'sets'}'
              '${best == null ? '' : ' · best ${describeSet(best)}'}',
          emphasis: true,
        )
      else if (started)
        _Tag(
          icon: Icons.timelapse,
          text: '$working of ${s.sets} sets',
          emphasis: true,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  done
                      ? Icons.check_circle
                      : s.exercise.isOutdoor
                      ? Icons.park_outlined
                      : s.exercise.isCardio
                      ? Icons.directions_run
                      : Icons.fitness_center,
                  size: 20,
                  color: done ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.exercise.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!done)
                      Text(
                        [s.prescription, ?s.equipmentLabel].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (status.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: status),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!done && (canLog || (canReplace && !started)))
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canLog)
                    FilledButton.tonalIcon(
                      onPressed: () => _log(context),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(started ? 'Log set ${working + 1}' : 'Log'),
                    ),
                  // A started exercise is not swapped out from under its sets.
                  if (canReplace && !started)
                    OutlinedButton.icon(
                      onPressed: () => _replace(context, ref),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Replace'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _log(BuildContext context) async {
    final logged = await showLogSuggestionSheet(context, suggestion);
    if (logged && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logged ${suggestion.exercise.name}.')),
      );
    }
  }

  Future<void> _replace(BuildContext context, WidgetRef ref) async {
    final engine = await ref.read(coachEngineProvider.future);
    if (!context.mounted) return;
    // A replacement replaces the plan's original slot, not itself.
    final original = replaced ?? suggestion.exercise;
    final onDay = {for (final s in day.exercises) s.exercise.id};
    final options = engine.swapOptionsFor(
      original,
      excludeIds: {...onDay, original.id},
    );
    final picked = await showModalBottomSheet<CatalogExercise>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SwapSheet(
        current: suggestion.exercise,
        original: replaced,
        options: [for (final e in options) engine.suggestFor(e)],
      ),
    );
    if (picked == null || !context.mounted) return;
    final swaps = ref.read(planSwapsProvider.notifier);
    if (picked.id == original.id) {
      await swaps.undo(day: day.date, originalExerciseId: original.id);
    } else {
      final saved = await swaps.swap(
        day: day.date,
        originalExerciseId: original.id,
        replacementExerciseId: picked.id,
      );
      if (!saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Swapped for now, but it could not be saved - it will reset '
              'when the app restarts.',
            ),
          ),
        );
      }
    }
  }

  static SetRecord? _bestOf(List<SetRecord> sets) {
    SetRecord? best;
    for (final set in sets) {
      if (!set.setType.countsAsVolume) continue;
      final load = (set.weight ?? 0) == 0 ? 0 : set.unit.toLb(set.weight!);
      final bestLoad = best == null || (best.weight ?? 0) == 0
          ? 0
          : best.unit.toLb(best.weight!);
      if (best == null ||
          load > bestLoad ||
          (load == bestLoad && (set.reps ?? 0) > (best.reps ?? 0))) {
        best = set;
      }
    }
    return best ?? (sets.isEmpty ? null : sets.first);
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text, required this.emphasis});

  final IconData icon;
  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = emphasis ? scheme.primaryContainer : Colors.transparent;
    final ink = emphasis ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasis ? scheme.primaryContainer : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Replace (exercise)": the top three alternatives for the same muscles,
/// each with its own prescription, plus "put the original back" after a swap.
class _SwapSheet extends StatelessWidget {
  const _SwapSheet({
    required this.current,
    required this.original,
    required this.options,
  });

  final CatalogExercise current;
  final CatalogExercise? original;
  final List<SuggestedSet> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = current.primaryMuscleGroups.map(muscleGroupLabel).join(', ');
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Replace ${current.name}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                current.isCardio
                    ? 'Other cardio that is free right now.'
                    : 'Top picks for the same muscles ($groups), on equipment '
                          'that is free right now.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nothing else trains these muscles on the floor today.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              for (final (i, s) in options.indexed)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: i == 0
                          ? scheme.secondary
                          : scheme.surfaceContainerHighest,
                      foregroundColor: i == 0
                          ? scheme.onSecondary
                          : scheme.onSurfaceVariant,
                      child: Text('${i + 1}'),
                    ),
                    title: Text(s.exercise.name),
                    subtitle: Text(
                      [
                        s.prescription,
                        s.exercise.primaryMuscleGroups
                            .map(muscleGroupLabel)
                            .join(', '),
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(s.exercise),
                  ),
                ),
              if (original != null) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(original),
                  icon: const Icon(Icons.undo),
                  label: Text('Put back ${original!.name}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One exercise with its prescription and, when allowed, a Log button.
class PlannedExerciseRow extends ConsumerWidget {
  const PlannedExerciseRow({
    super.key,
    required this.suggestion,
    this.canLog = true,
    this.doneToday = false,
    this.tip,
  });

  final SuggestedSet suggestion;
  final bool canLog;

  /// Already logged today: [suggestion] is then next time's prescription,
  /// so the row says so and offers no Log button.
  final bool doneToday;
  final String? tip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = suggestion;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            doneToday
                ? Icons.check_circle
                : s.exercise.isOutdoor
                ? Icons.park_outlined
                : s.exercise.isCardio
                ? Icons.directions_run
                : Icons.fitness_center,
            size: 20,
            color: doneToday ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.exercise.name, style: theme.textTheme.bodyLarge),
                if (doneToday)
                  Text(
                    'Done today',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  [
                    if (doneToday)
                      'Next time: ${s.prescription}'
                    else
                      s.prescription,
                    ?s.equipmentLabel,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (tip != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    tip!,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (canLog && !doneToday)
            TextButton(
              onPressed: () async {
                final logged = await showLogSuggestionSheet(
                  context,
                  s,
                  aiTip: tip,
                );
                if (logged && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Logged ${s.exercise.name}.')),
                  );
                }
              },
              child: const Text('Log'),
            ),
        ],
      ),
    );
  }
}
