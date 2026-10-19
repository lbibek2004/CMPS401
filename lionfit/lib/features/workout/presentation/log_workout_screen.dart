import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../../core/training/muscle_labels.dart';
import '../data/workout_repository.dart';
import '../domain/workout_models.dart';
import 'exercise_picker_sheet.dart';

/// `/log` - today's session: add exercises from the catalog, log sets.
///
/// The session row is created on the first logged set, not on open, so
/// browsing this screen never leaves an empty workout behind.
class LogWorkoutScreen extends ConsumerWidget {
  const LogWorkoutScreen({super.key});

  Future<void> _addExercise(BuildContext context, WidgetRef ref) async {
    final picked = await showExercisePicker(context);
    if (picked != null) {
      ref.read(todaySessionProvider.notifier).addExercise(picked.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(todaySessionProvider);
    final catalog = ref.watch(exerciseCatalogProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.home)),
        title: const Text("Today's workout"),
        actions: [
          TextButton.icon(
            onPressed: () => context.go(Routes.muscleMap),
            icon: const Icon(Icons.accessibility_new_outlined),
            label: const Text('Muscle map'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: session.hasValue
          ? FloatingActionButton.extended(
              onPressed: () => _addExercise(context, ref),
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
          onAddExercise: () => _addExercise(context, ref),
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
    required this.onAddExercise,
  });

  final TodaySession session;
  final Map<String, CatalogExercise> exercisesById;
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
                _dateLabel(session.day),
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
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ExerciseCard(
                        key: ValueKey(id),
                        exercise: exercise,
                        sets: session.setsFor(id),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
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

  static String _dateLabel(DateTime day) =>
      '${_weekdays[day.weekday - 1]}, ${_months[day.month - 1]} ${day.day}';
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

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({super.key, required this.exercise, required this.sets});

  final CatalogExercise exercise;
  final List<SetRecord> sets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = LionFitTokens.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(tokens.radiusLg),
        border: Border.all(color: scheme.outlineVariant),
      ),
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
                          _MuscleTag(
                            label: muscleGroupLabel(group),
                            primary: true,
                          ),
                        for (final group in exercise.secondaryMuscleGroups)
                          _MuscleTag(
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
                  tooltip: 'Remove exercise',
                  onPressed: () => ref
                      .read(todaySessionProvider.notifier)
                      .removeExercise(exercise.id),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (sets.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final set in sets) _SetRow(set: set),
          ],
          const SizedBox(height: 12),
          _AddSetForm(
            exercise: exercise,
            previous: sets.isEmpty ? null : sets.last,
          ),
        ],
      ),
    );
  }
}

class _MuscleTag extends StatelessWidget {
  const _MuscleTag({required this.label, required this.primary});

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

class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({required this.set});

  final SetRecord set;

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
    final tokens = LionFitTokens.of(context);
    final set = widget.set;
    final (fill, ink) = switch (set.setType) {
      SetType.warmUp => (tokens.setTypeWarmUp, tokens.onSetTypeWarmUp),
      SetType.working => (tokens.setTypeWorking, tokens.onSetTypeWorking),
      SetType.dropSet => (tokens.setTypeDropSet, tokens.onSetTypeDropSet),
      SetType.superSet => (tokens.setTypeSuperSet, tokens.onSetTypeSuperSet),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
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
          ),
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
            tooltip: 'Delete set ${set.setIndex}',
            onPressed: _deleting ? null : _delete,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}

enum _EffortKind { rpe, rir }

class _AddSetForm extends ConsumerStatefulWidget {
  const _AddSetForm({required this.exercise, this.previous});

  final CatalogExercise exercise;
  final SetRecord? previous;

  @override
  ConsumerState<_AddSetForm> createState() => _AddSetFormState();
}

class _AddSetFormState extends ConsumerState<_AddSetForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  final _effort = TextEditingController();
  late WeightUnit _unit;
  late SetType _setType;
  _EffortKind _effortKind = _EffortKind.rpe;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final previous = widget.previous;
    // Pre-fill from the last set: the next set is usually the same load.
    _weight = TextEditingController(
      text: previous?.weight == null ? '' : formatTrimmed(previous!.weight!),
    );
    _reps = TextEditingController(text: previous?.reps?.toString() ?? '');
    _unit = previous?.unit ?? WeightUnit.lb;
    _setType = previous?.setType ?? SetType.working;
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _effort.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final effort = _effort.text.trim();
    final weightText = _weight.text.trim();
    try {
      await ref
          .read(todaySessionProvider.notifier)
          .logSet(
            NewSet(
              exerciseId: widget.exercise.id,
              setType: _setType,
              unit: _unit,
              weight: weightText.isEmpty ? null : double.parse(weightText),
              reps: int.parse(_reps.text.trim()),
              rpe: _effortKind == _EffortKind.rpe && effort.isNotEmpty
                  ? double.parse(effort)
                  : null,
              rir: _effortKind == _EffortKind.rir && effort.isNotEmpty
                  ? int.parse(effort)
                  : null,
            ),
          );
      _effort.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Set not saved: ${_describe(error)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _describe(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed to fetch') ||
        text.contains('ClientException')) {
      return 'no connection. Your input is still here - try again.';
    }
    return text;
  }

  String? _validateWeight(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null; // Bodyweight.
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) return 'Enter a weight';
    if (parsed > 2000) return 'Too heavy';
    return null;
  }

  String? _validateReps(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 1) return 'Reps';
    if (parsed > 1000) return 'Too many';
    return null;
  }

  String? _validateEffort(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null; // Optional.
    if (_effortKind == _EffortKind.rpe) {
      final parsed = double.tryParse(text);
      if (parsed == null || parsed < 1 || parsed > 10) return '1-10';
    } else {
      final parsed = int.tryParse(text);
      if (parsed == null || parsed < 0 || parsed > 10) return '0-10';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final digits = [FilteringTextInputFormatter.digitsOnly];

    final weightField = TextFormField(
      controller: _weight,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: decimal,
      decoration: InputDecoration(
        labelText: 'Weight',
        hintText: widget.exercise.isBodyweightOnly ? 'Bodyweight' : null,
        isDense: true,
      ),
      validator: _validateWeight,
    );
    final repsField = TextFormField(
      controller: _reps,
      keyboardType: TextInputType.number,
      inputFormatters: digits,
      decoration: const InputDecoration(labelText: 'Reps', isDense: true),
      validator: _validateReps,
      onFieldSubmitted: (_) => _submit(),
    );
    final effortField = TextFormField(
      controller: _effort,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: _effortKind == _EffortKind.rpe ? decimal : digits,
      decoration: InputDecoration(
        labelText: _effortKind == _EffortKind.rpe ? 'RPE' : 'RIR',
        hintText: 'Optional',
        isDense: true,
      ),
      validator: _validateEffort,
    );
    final unitToggle = SegmentedButton<WeightUnit>(
      segments: const [
        ButtonSegment(value: WeightUnit.lb, label: Text('lb')),
        ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
      ],
      selected: {_unit},
      showSelectedIcon: false,
      onSelectionChanged: (value) => setState(() => _unit = value.first),
    );
    final effortToggle = SegmentedButton<_EffortKind>(
      segments: const [
        ButtonSegment(value: _EffortKind.rpe, label: Text('RPE')),
        ButtonSegment(value: _EffortKind.rir, label: Text('RIR')),
      ],
      selected: {_effortKind},
      showSelectedIcon: false,
      onSelectionChanged: (value) => setState(() {
        _effortKind = value.first;
        _effort.clear();
      }),
    );
    final typeMenu = DropdownButtonFormField<SetType>(
      initialValue: _setType,
      isDense: true,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Set type', isDense: true),
      items: [
        for (final type in SetType.values)
          DropdownMenuItem(value: type, child: Text(setTypeLabel(type))),
      ],
      onChanged: (value) => setState(() => _setType = value ?? _setType),
    );
    final submit = FilledButton.icon(
      onPressed: _saving ? null : _submit,
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.check),
      label: const Text('Log set'),
    );

    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          if (wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: weightField),
                    const SizedBox(width: 8),
                    unitToggle,
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: repsField),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: typeMenu),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    effortToggle,
                    const SizedBox(width: 12),
                    Expanded(child: effortField),
                    const SizedBox(width: 12),
                    submit,
                  ],
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: weightField),
                  const SizedBox(width: 8),
                  unitToggle,
                ],
              ),
              const SizedBox(height: 12),
              repsField,
              const SizedBox(height: 12),
              typeMenu,
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  effortToggle,
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 120,
                      maxWidth: 200,
                    ),
                    child: effortField,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              submit,
            ],
          );
        },
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
