import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../../core/training/muscle_labels.dart';
import '../../../core/training/one_rep_max.dart';
import '../../coach/data/coach_providers.dart';
import '../data/workout_repository.dart';
import '../domain/training_profile.dart';
import '../domain/workout_models.dart';
import 'effort_slider.dart';
import 'exercise_picker_sheet.dart';
import 'set_form.dart';

/// `/log` - today's session: add exercises from the catalog, log sets.
///
/// **One exercise is open at a time.** Adding an exercise opens it and folds
/// every other card down to a one-line summary; "Done" folds the open one;
/// "Edit" on a summary reopens it, where each set can be edited or deleted.
/// Exercises that already have sets start folded when the screen opens.
///
/// The session row is created on the first logged set, not on open, so
/// browsing this screen never leaves an empty workout behind.
class LogWorkoutScreen extends ConsumerStatefulWidget {
  const LogWorkoutScreen({super.key});

  @override
  ConsumerState<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends ConsumerState<LogWorkoutScreen> {
  /// The one open card. Null = everything folded.
  String? _openId;
  bool _initialised = false;

  Future<void> _addExercise() async {
    final picked = await showExercisePicker(context);
    if (picked == null) return;
    ref.read(todaySessionProvider.notifier).addExercise(picked.id);
    setState(() => _openId = picked.id);
  }

  void _pickInitialOpen(TodaySession session) {
    if (_initialised) return;
    _initialised = true;
    // Open the first exercise that has nothing logged yet, if any.
    for (final id in session.exerciseOrder) {
      if (session.setsFor(id).isEmpty) {
        _openId = id;
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(todaySessionProvider);
    final catalog = ref.watch(exerciseCatalogProvider);
    if (session case AsyncData(:final value)) _pickInitialOpen(value);

    // No app bar: the shell's navigation carries the title.
    return Scaffold(
      floatingActionButton: session.hasValue
          ? FloatingActionButton.extended(
              onPressed: _addExercise,
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            )
          : null,
      body: switch ((session, catalog)) {
        (AsyncError(), _) || (_, AsyncError()) => _LoadError(
          onRetry: () {
            ref.invalidate(todaySessionProvider);
            ref.invalidate(exerciseCatalogProvider);
          },
        ),
        (AsyncData(value: final s), AsyncData(value: final c)) => _SessionBody(
          session: s,
          exercisesById: {for (final e in c) e.id: e},
          openId: _openId,
          onOpen: (id) => setState(() => _openId = id),
          onAddExercise: _addExercise,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.session,
    required this.exercisesById,
    required this.openId,
    required this.onOpen,
    required this.onAddExercise,
  });

  final TodaySession session;
  final Map<String, CatalogExercise> exercisesById;
  final String? openId;
  final ValueChanged<String?> onOpen;
  final VoidCallback onAddExercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalSets = session.sets.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                longDateLabel(session.day),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                totalSets == 0
                    ? 'Nothing logged yet today.'
                    : '$totalSets ${totalSets == 1 ? 'set' : 'sets'} logged '
                          'across ${session.exerciseOrder.length} '
                          '${session.exerciseOrder.length == 1 ? 'exercise' : 'exercises'}.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              if (session.exerciseOrder.isEmpty)
                _EmptySession(onAddExercise: onAddExercise)
              else
                for (final id in session.exerciseOrder)
                  if (exercisesById[id] case final exercise?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        alignment: Alignment.topCenter,
                        child: id == openId
                            ? _OpenExerciseCard(
                                key: ValueKey('open-$id'),
                                exercise: exercise,
                                sets: session.setsFor(id),
                                onDone: () => onOpen(null),
                              )
                            : _FoldedExerciseCard(
                                key: ValueKey('folded-$id'),
                                exercise: exercise,
                                sets: session.setsFor(id),
                                onEdit: () => onOpen(id),
                              ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Monday, October 19".
String longDateLabel(DateTime day) =>
    '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';

/// "Mon, Oct 19".
String shortDateLabel(DateTime day) =>
    '${_weekdays[day.weekday - 1].substring(0, 3)}, '
    '${_months[day.month - 1].substring(0, 3)} ${day.day}';

/// The heaviest set by estimated 1RM, or the most reps without load.
SetRecord? bestSetOf(List<SetRecord> sets) {
  SetRecord? best;
  double? bestScore;
  for (final set in sets) {
    if (!set.setType.countsAsVolume) continue;
    final score =
        e1rmForSet(set.toLoggedSet()) ?? (set.reps ?? 0).toDouble() / 1000;
    if (bestScore == null || score > bestScore) {
      best = set;
      bestScore = score;
    }
  }
  return best ?? (sets.isEmpty ? null : sets.first);
}

class _EmptySession extends StatelessWidget {
  const _EmptySession({required this.onAddExercise});

  final VoidCallback onAddExercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fitness_center_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Pick your first exercise',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Every set you log here lights up the muscles it trained on the '
            '3D muscle map.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddExercise,
            icon: const Icon(Icons.add),
            label: const Text('Add exercise'),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration(BuildContext context, {bool open = false}) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: scheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(LionFitTokens.of(context).radiusLg),
    border: Border.all(
      color: open ? scheme.primary : scheme.outlineVariant,
      width: open ? 1.5 : 1,
    ),
  );
}

/// One line per exercise once it is recorded: name, set count, best set.
class _FoldedExerciseCard extends ConsumerWidget {
  const _FoldedExerciseCard({
    super.key,
    required this.exercise,
    required this.sets,
    required this.onEdit,
  });

  final CatalogExercise exercise;
  final List<SetRecord> sets;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final best = bestSetOf(sets);
    final summary = sets.isEmpty
        ? 'No sets yet'
        : '${sets.length} ${sets.length == 1 ? 'set' : 'sets'}'
              '${best == null ? '' : ' · best ${describeSet(best)}'}';

    return Container(
      decoration: _cardDecoration(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(LionFitTokens.of(context).radiusLg),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                sets.isEmpty
                    ? Icons.radio_button_unchecked
                    : Icons.check_circle,
                color: sets.isEmpty ? scheme.onSurfaceVariant : scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (sets.isEmpty)
                IconButton(
                  tooltip: 'Remove ${exercise.name}',
                  onPressed: () => ref
                      .read(todaySessionProvider.notifier)
                      .removeExercise(exercise.id),
                  icon: const Icon(Icons.close),
                ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(sets.isEmpty ? 'Log' : 'Edit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenExerciseCard extends ConsumerStatefulWidget {
  const _OpenExerciseCard({
    super.key,
    required this.exercise,
    required this.sets,
    required this.onDone,
  });

  final CatalogExercise exercise;
  final List<SetRecord> sets;
  final VoidCallback onDone;

  @override
  ConsumerState<_OpenExerciseCard> createState() => _OpenExerciseCardState();
}

class _OpenExerciseCardState extends ConsumerState<_OpenExerciseCard> {
  /// The set being edited in place, if any.
  String? _editingSetId;

  void _showError(Object error, String what) {
    final text = error.toString();
    final offline =
        text.contains('SocketException') ||
        text.contains('Failed to fetch') ||
        text.contains('ClientException');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          offline
              ? '$what: no connection. Your input is still here - try again.'
              : '$what: $text',
        ),
      ),
    );
  }

  Future<void> _logSet(NewSet set) async {
    try {
      // Saving the set also starts the rest timer (TodaySessionController).
      await ref.read(todaySessionProvider.notifier).logSet(set);
    } catch (error) {
      if (mounted) _showError(error, 'Set not saved');
      rethrow;
    }
  }

  Future<void> _updateSet(String id, NewSet set) async {
    try {
      await ref.read(todaySessionProvider.notifier).updateSet(id, set);
      if (mounted) setState(() => _editingSetId = null);
    } catch (error) {
      if (mounted) _showError(error, 'Set not updated');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final exercise = widget.exercise;
    final sets = widget.sets;
    final profile =
        ref.watch(trainingProfileProvider).value ?? const TrainingProfile();
    final suggestion = sets.isEmpty
        ? ref.watch(coachEngineProvider).value?.suggestFor(exercise)
        : null;
    final last = sets.isEmpty ? null : sets.last;

    // Pre-fill: the last set if there is one (the next set is usually the
    // same), else the coach's suggestion, else blank. Effort starts on the
    // profile's preferred scale so the slider is one drag away.
    final draft = last != null
        ? SetDraft.fromSet(last)
        : SetDraft(
            weight: suggestion?.weight,
            unit: suggestion?.unit ?? profile.unit,
            reps: suggestion?.reps,
            effort: EffortEntry.defaultFor(profile.effortScale),
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      decoration: _cardDecoration(context, open: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final group in exercise.primaryMuscleGroups)
                          MuscleTag(
                            label: muscleGroupLabel(group),
                            primary: true,
                          ),
                        for (final group in exercise.secondaryMuscleGroups)
                          MuscleTag(
                            label: muscleGroupLabel(group),
                            primary: false,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (sets.isEmpty)
                IconButton(
                  tooltip: 'Remove ${exercise.name}',
                  onPressed: () {
                    ref
                        .read(todaySessionProvider.notifier)
                        .removeExercise(exercise.id);
                    widget.onDone();
                  },
                  icon: const Icon(Icons.close),
                )
              else
                FilledButton.tonal(
                  onPressed: widget.onDone,
                  child: const Text('Done'),
                ),
            ],
          ),
          if (suggestion != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(
                  LionFitTokens.of(context).radiusSm,
                ),
              ),
              child: Text(
                'Suggested: ${suggestion.prescription}. ${suggestion.reason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (sets.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final set in sets)
              if (set.id == _editingSetId)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(
                        LionFitTokens.of(context).radiusSm,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Edit set ${set.setIndex}',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 12),
                        SetForm(
                          key: ValueKey('edit-${set.id}'),
                          exercise: exercise,
                          initial: SetDraft.fromSet(set),
                          submitLabel: 'Save',
                          onSubmit: (updated) => _updateSet(set.id, updated),
                          onCancel: () => setState(() => _editingSetId = null),
                        ),
                      ],
                    ),
                  ),
                )
              else
                _SetRow(
                  set: set,
                  onEdit: () => setState(() => _editingSetId = set.id),
                ),
          ],
          if (_editingSetId == null) ...[
            const SizedBox(height: 16),
            SetForm(
              // Re-keyed per set count so the pre-fill follows the last set,
              // and once more when the coach's suggestion finishes loading.
              key: ValueKey(
                'add-${exercise.id}-${sets.length}-${suggestion != null}',
              ),
              exercise: exercise,
              initial: draft,
              submitLabel: 'Log set ${sets.length + 1}',
              onSubmit: _logSet,
            ),
          ],
        ],
      ),
    );
  }
}

class MuscleTag extends StatelessWidget {
  const MuscleTag({super.key, required this.label, required this.primary});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: primary ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: primary ? scheme.primaryContainer : scheme.outlineVariant,
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: primary ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The numbered chip for a set, coloured by set type.
class SetIndexChip extends StatelessWidget {
  const SetIndexChip({super.key, required this.set});

  final SetRecord set;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = LionFitTokens.of(context);
    final (fill, ink) = switch (set.setType) {
      SetType.warmUp => (tokens.setTypeWarmUp, tokens.onSetTypeWarmUp),
      SetType.working => (tokens.setTypeWorking, tokens.onSetTypeWorking),
      SetType.dropSet => (tokens.setTypeDropSet, tokens.onSetTypeDropSet),
      SetType.superSet => (tokens.setTypeSuperSet, tokens.onSetTypeSuperSet),
    };
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Text(
        '${set.setIndex}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({required this.set, required this.onEdit});

  final SetRecord set;
  final VoidCallback onEdit;

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  bool _deleting = false;

  Future<void> _delete() async {
    setState(() => _deleting = true);
    try {
      await ref.read(todaySessionProvider.notifier).deleteSet(widget.set.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete that set. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final set = widget.set;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SetIndexChip(set: set),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: describeSet(set),
                    style: theme.textTheme.bodyLarge,
                  ),
                  TextSpan(
                    text: '  ${setTypeLabel(set.setType)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Edit set ${set.setIndex}',
            onPressed: _deleting ? null : widget.onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Delete set ${set.setIndex}',
            onPressed: _deleting ? null : _delete,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              "Could not load today's workout.",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
