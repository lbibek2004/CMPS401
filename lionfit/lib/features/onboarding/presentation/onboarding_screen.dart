import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../profile/data/profile_providers.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/domain/workout_models.dart';
import '../domain/survey.dart';

/// `/welcome` - the five-question survey a new account answers once.
///
/// It gives the coach something better than a blank slate: the goal and
/// schedule shape the weekly plan, experience and effort set how hard it
/// pushes, and the optional "what can you lift now?" answers become
/// first-session weights (`coach/domain/starting_load.dart`). Skipping that
/// last step is fine - the first week is then a light calibration week.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

const _stepCount = 5;

class _LiftAnswer {
  _LiftAnswer();

  String? exerciseId;
  final weight = TextEditingController();
  final reps = TextEditingController();

  void dispose() {
    weight.dispose();
    reps.dispose();
  }
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  TrainingProfile? _answers;
  final _lifts = [for (final _ in kSurveyLiftCategories) _LiftAnswer()];
  final _bodyweight = TextEditingController();
  final _liftsForm = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final lift in _lifts) {
      lift.dispose();
    }
    _bodyweight.dispose();
    super.dispose();
  }

  TrainingProfile get _a => _answers!;

  void _set(TrainingProfile next) => setState(() => _answers = next);

  bool get _canContinue => switch (_step) {
    2 => _a.experience != null,
    _ => true,
  };

  Future<void> _finish({required bool withLifts}) async {
    if (withLifts && !(_liftsForm.currentState?.validate() ?? true)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final unit = _a.unit;
    final bodyweight = double.tryParse(_bodyweight.text.trim());
    final baselines = <StrengthBaseline>[
      if (withLifts)
        for (final lift in _lifts)
          if (lift.exerciseId != null)
            if (double.tryParse(lift.weight.text.trim()) case final w?)
              if (int.tryParse(lift.reps.text.trim()) case final r?)
                if (w > 0 && r > 0)
                  StrengthBaseline(
                    exerciseId: lift.exerciseId!,
                    weight: w,
                    unit: unit,
                    reps: r,
                  ),
    ];
    final bodyweightLb = bodyweight == null ? null : unit.toLb(bodyweight);
    final answers = _a.copyWith(
      // Kept on Skip too, as long as it is plausible.
      bodyweightLb: () =>
          bodyweightLb != null && bodyweightLb >= 50 && bodyweightLb <= 700
          ? bodyweightLb
          : null,
    );
    try {
      // Bounded: a request that never answers must not leave the button
      // spinning with no way out. Retrying is safe - every write is an
      // overwrite, not an append.
      await ref
          .read(profileActionsProvider)
          .completeOnboarding(answers, baselines)
          .timeout(const Duration(seconds: 30));
      if (mounted) context.go(Routes.home);
    } catch (error) {
      debugPrint('survey not saved: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (error) {
          ProfileNotSaved() =>
            'Your answers were not saved to your profile. Try again; if it '
                'keeps happening, sign out and back in.',
          TimeoutException() =>
            'Saving is taking too long. Check your connection and try again.',
          _ =>
            'Could not save your answers. Check your connection and try '
                'again.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(trainingProfileProvider);
    final catalog = ref.watch(activeCatalogProvider).value ?? const [];
    _answers ??= profile.value;
    final theme = Theme.of(context);

    if (_answers == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final body = switch (_step) {
      0 => _goalStep(),
      1 => _daysStep(),
      2 => _experienceStep(),
      3 => _effortStep(),
      _ => _liftsStep(catalog),
    };
    final last = _step == _stepCount - 1;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/android-chrome-192x192.png',
                        width: 32,
                        height: 32,
                        semanticLabel: 'LionFit',
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Step ${_step + 1} of $_stepCount',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      // A retake can be abandoned; the first survey cannot.
                      if (profile.value?.needsOnboarding == false)
                        IconButton(
                          tooltip: 'Close survey',
                          onPressed: () => context.go(Routes.profile),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / _stepCount,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_a.hasExtendedColumns) ...[
                          const _NotStoredNotice(),
                          const SizedBox(height: 20),
                        ],
                        body,
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Row(
                    children: [
                      if (_step > 0)
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _step--),
                          child: const Text('Back'),
                        ),
                      const SizedBox(width: 8),
                      // Wraps under itself on a narrow phone at large text.
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (last)
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => _finish(withLifts: false),
                                child: const Text('Skip'),
                              ),
                            FilledButton(
                              onPressed: _saving || !_canContinue
                                  ? null
                                  : last
                                  ? () => _finish(withLifts: true)
                                  : () => setState(() => _step++),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(120, 48),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(last ? 'Build my plan' : 'Next'),
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
      ),
    );
  }

  Widget _heading(String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _goalStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'What are you training for?',
        'This sets your rep ranges, how many sets, and how much cardio goes '
            'into the week.',
      ),
      for (final (goal, note) in const [
        (TrainingGoal.muscleGain, 'More sets, heavier, 6-15 reps'),
        (TrainingGoal.weightLoss, 'Higher reps, cardio every day'),
        (TrainingGoal.generalFitness, 'A bit of everything'),
      ])
        _Choice(
          title: goal.label,
          subtitle: note,
          selected: _a.goal == goal,
          onTap: () => _set(_a.copyWith(goal: goal)),
        ),
    ],
  );

  Widget _daysStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'How many days a week can you train?',
        'Your plan splits the week to match. You can change this any time '
            'from your profile.',
      ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var d = 3; d <= 7; d++)
            ChoiceChip(
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('$d days'),
              ),
              selected: _a.daysPerWeek == d,
              onSelected: (_) => _set(_a.copyWith(daysPerWeek: d)),
            ),
        ],
      ),
    ],
  );

  Widget _experienceStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        'How long have you been lifting?',
        'Newer lifters start lighter, with machines before free barbells.',
      ),
      for (final e in TrainingExperience.values)
        _Choice(
          title: e.label,
          subtitle: e.description,
          selected: _a.experience == e,
          onTap: () => _set(_a.copyWith(experience: e)),
        ),
    ],
  );

  Widget _effortStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'How do you like to rate effort?',
          'After each set you say how hard it was. That rating is how the '
              'app picks your next weight.',
        ),
        _Choice(
          title: 'RPE - how hard it felt',
          subtitle: '10 = nothing left, 8 = two reps left',
          selected: _a.effortScale == EffortScale.rpe,
          onTap: () => _set(_a.copyWith(effortScale: EffortScale.rpe)),
        ),
        _Choice(
          title: 'RIR - reps left in the tank',
          subtitle: '0 = could not do another, 2 = two more were there',
          selected: _a.effortScale == EffortScale.rir,
          onTap: () => _set(_a.copyWith(effortScale: EffortScale.rir)),
        ),
        const SizedBox(height: 20),
        Text(
          'How hard should working sets be?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final rpe in kTargetRpeChoices)
              ChoiceChip(
                label: Text(targetEffortLabel(rpe, _a.effortScale)),
                selected: _a.targetRpe == rpe,
                onSelected: (_) => _set(_a.copyWith(targetRpe: rpe)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Weights in',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final unit in WeightUnit.values)
              ChoiceChip(
                label: Text(
                  unit == WeightUnit.lb ? 'Pounds (lb)' : 'Kilos (kg)',
                ),
                selected: _a.unit == unit,
                onSelected: (_) => _set(_a.copyWith(unit: unit)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _liftsStep(List<CatalogExercise> catalog) {
    final theme = Theme.of(context);
    final unit = _a.unit.wireName;
    final isNew = _a.experience == TrainingExperience.brandNew;
    return Form(
      key: _liftsForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            'What can you lift right now?',
            isNew
                ? 'Optional, and fine to skip - your first week starts light '
                      'and the app learns your weights from how each set '
                      'feels.'
                : 'Optional. A set you could do today for each, with a rep '
                      'or two left. Fill in any you know; the app estimates '
                      'the rest and skips the guesswork.',
          ),
          TextFormField(
            controller: _bodyweight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: 'Bodyweight (optional)',
              suffixText: unit,
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return null;
              final parsed = double.tryParse(t);
              if (parsed == null) return 'Enter a number';
              final lb = _a.unit.toLb(parsed);
              return lb < 50 || lb > 700
                  ? 'That looks off - check the unit'
                  : null;
            },
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < kSurveyLiftCategories.length; i++)
            _LiftRow(
              category: kSurveyLiftCategories[i],
              options: surveyOptions(catalog, kSurveyLiftCategories[i]),
              answer: _lifts[i],
              unit: unit,
              onChanged: () => setState(() {}),
            ),
          Text(
            'Nothing here is final - every logged set updates your numbers.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(LionFitTokens.of(context).radiusLg);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerLow,
              borderRadius: radius,
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected ? scheme.onPrimaryContainer : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiftRow extends StatelessWidget {
  const _LiftRow({
    required this.category,
    required this.options,
    required this.answer,
    required this.unit,
    required this.onChanged,
  });

  final SurveyLiftCategory category;
  final List<CatalogExercise> options;
  final _LiftAnswer answer;
  final String unit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (options.isEmpty) return const SizedBox.shrink();
    answer.exerciseId ??= options.first.id;
    final filledWeight = answer.weight.text.trim().isNotEmpty;
    final filledReps = answer.reps.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            category.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            category.example,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: answer.exerciseId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Exercise'),
            items: [
              for (final e in options)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(e.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) {
              answer.exerciseId = id;
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: answer.weight,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Weight',
                    suffixText: unit,
                  ),
                  onChanged: (_) => onChanged(),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return filledReps ? 'Add a weight' : null;
                    final parsed = double.tryParse(t);
                    if (parsed == null || parsed <= 0) return 'Enter a weight';
                    return parsed > 2000 ? 'Too heavy' : null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: answer.reps,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Reps'),
                  onChanged: (_) => onChanged(),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return filledWeight ? 'Add reps' : null;
                    final parsed = int.tryParse(t);
                    if (parsed == null || parsed < 1) return 'Reps';
                    return parsed > 50 ? 'Max 50' : null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when the database lacks migration 0009: only goal, days, unit and
/// effort scale can be saved, so the user is told rather than left guessing
/// why nothing changed.
class _NotStoredNotice extends StatelessWidget {
  const _NotStoredNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(LionFitTokens.of(context).radiusSm),
      ),
      child: Text(
        'The database has not been updated for the survey yet (migration '
        '0009). Goal, days, unit and effort scale will save; experience, '
        'target effort, bodyweight and your current lifts will not, so '
        'suggested weights will not change.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onErrorContainer,
          height: 1.4,
        ),
      ),
    );
  }
}
