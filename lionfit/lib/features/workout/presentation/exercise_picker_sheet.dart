import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../../core/training/muscle_labels.dart';
import '../data/workout_repository.dart';
import '../domain/workout_models.dart';

/// Opens the catalog picker and resolves to the chosen exercise, or null.
Future<CatalogExercise?> showExercisePicker(BuildContext context) {
  return showModalBottomSheet<CatalogExercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.9,
      child: ExercisePickerSheet(),
    ),
  );
}

/// Search + muscle filter over the `exercises` catalog.
class ExercisePickerSheet extends ConsumerStatefulWidget {
  const ExercisePickerSheet({super.key});

  @override
  ConsumerState<ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  String _query = '';
  MuscleGroup? _muscle;

  List<CatalogExercise> _filter(List<CatalogExercise> all) {
    final query = _query.trim().toLowerCase();
    return [
      for (final exercise in all)
        if ((query.isEmpty || exercise.name.toLowerCase().contains(query)) &&
            (_muscle == null || exercise.primaryMuscleGroups.contains(_muscle)))
          exercise,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(exerciseCatalogProvider);
    final labels = ref.watch(equipmentLabelsProvider).value ?? const {};

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Add an exercise',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search exercises',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _MuscleChip(
                    label: 'All',
                    selected: _muscle == null,
                    onSelected: () => setState(() => _muscle = null),
                  ),
                  for (final group in MuscleGroup.values)
                    _MuscleChip(
                      label: muscleGroupLabel(group),
                      selected: _muscle == group,
                      onSelected: () => setState(
                        () => _muscle = _muscle == group ? null : group,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: catalog.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _CatalogError(
                  onRetry: () => ref.invalidate(exerciseCatalogProvider),
                ),
                data: (all) {
                  final matches = _filter(all);
                  if (matches.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          all.isEmpty
                              ? 'The exercise catalog is empty. Apply the '
                                    'seed migrations in supabase/migrations/.'
                              : 'No exercise matches that search.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _ExerciseTile(
                      exercise: matches[index],
                      equipmentLabels: labels,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MuscleChip extends StatelessWidget {
  const _MuscleChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({required this.exercise, required this.equipmentLabels});

  final CatalogExercise exercise;
  final Map<String, String> equipmentLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = LionFitTokens.of(context);
    final muscles = exercise.primaryMuscleGroups
        .map(muscleGroupLabel)
        .join(', ');
    final equipment = exercise.requiredEquipment
        .map((slug) => equipmentLabels[slug] ?? slug)
        .join(' + ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      title: Text(exercise.name),
      subtitle: Text(
        equipment.isEmpty ? muscles : '$muscles · $equipment',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: exercise.isDemoData
          ? Tooltip(
              message:
                  'Uses placeholder equipment that is not confirmed '
                  'at Pennington yet.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(tokens.radiusPill),
                ),
                child: Text(
                  'Demo',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          : null,
      onTap: () => Navigator.of(context).pop(exercise),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load the exercise catalog.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
