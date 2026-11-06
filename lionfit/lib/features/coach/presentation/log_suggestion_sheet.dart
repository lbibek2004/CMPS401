import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/training/models.dart';
import '../../../core/training/muscle_labels.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/domain/workout_models.dart';
import '../../workout/presentation/effort_slider.dart';
import '../domain/coach_engine.dart';

/// Opens the log sheet for the **next set** of [suggestion] ("Set 2 of 3").
/// Resolves to true when the set was saved.
///
/// One set per open, never several: each set gets its own effort rating, and
/// saving it starts the rest timer (`TodaySessionController.logSet`). The
/// fields start from the set just done today, or from the suggestion for the
/// first set, and are all editable - a suggestion is a starting point.
Future<bool> showLogSuggestionSheet(
  BuildContext context,
  SuggestedSet suggestion, {
  String? aiTip,
}) async {
  final logged = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => LogSuggestionSheet(suggestion: suggestion, aiTip: aiTip),
  );
  return logged ?? false;
}

class LogSuggestionSheet extends ConsumerStatefulWidget {
  const LogSuggestionSheet({super.key, required this.suggestion, this.aiTip});

  final SuggestedSet suggestion;
  final String? aiTip;

  @override
  ConsumerState<LogSuggestionSheet> createState() => _LogSuggestionSheetState();
}

class _LogSuggestionSheetState extends ConsumerState<LogSuggestionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  late WeightUnit _unit;
  EffortEntry? _effort;

  /// Sets of this exercise already logged today; this one is number
  /// [_done] + 1. Read once when the sheet opens.
  late final int _done;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.suggestion;
    // Today's session when it is loaded (it updates the instant a set is
    // saved); otherwise today's rows from the history.
    final day = calendarDay(DateTime.now());
    final source =
        ref.read(todaySessionProvider).value?.setsFor(s.exercise.id) ??
        [
          for (final set in ref.read(trainingHistoryProvider).value ?? const [])
            if (set.performedOn == day && set.exerciseId == s.exercise.id) set,
        ];
    final today = [
      for (final set in source)
        if (set.setType.countsAsVolume) set,
    ];
    _done = today.length;
    // The next set is usually the same as the last one, so it starts there.
    final last = today.isEmpty ? null : today.last;
    final weight = last != null ? last.weight : s.weight;
    _weight = TextEditingController(
      text: weight == null || weight == 0 ? '' : formatTrimmed(weight),
    );
    _reps = TextEditingController(text: '${last?.reps ?? s.reps}');
    _unit = last?.unit ?? s.unit;
    if (last != null && (last.rpe != null || last.rir != null)) {
      _effort = EffortEntry.fromSet(rpe: last.rpe, rir: last.rir);
    }
  }

  int get _setNumber => _done + 1;

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  Future<void> _log() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final weightText = _weight.text.trim();
    final set = NewSet(
      exerciseId: widget.suggestion.exercise.id,
      setType: SetType.working,
      unit: _unit,
      weight: weightText.isEmpty ? null : double.parse(weightText),
      reps: int.parse(_reps.text.trim()),
      // The rating is what lets the coach move the next load; without it a
      // single session can only be repeated.
      rpe: _effort?.rpe,
      rir: _effort?.rir,
    );
    try {
      await ref.read(todaySessionProvider.notifier).logSet(set);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Not logged: check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.suggestion;
    final exercise = s.exercise;
    final cardio = s.basis == SuggestionBasis.cardio;
    // Starts at the profile's target effort on its preferred scale.
    _effort ??= () {
      final profile =
          ref.read(trainingProfileProvider).value ?? const TrainingProfile();
      return profile.effortScale == EffortScale.rpe
          ? EffortEntry.rpe(profile.targetRpe)
          : EffortEntry.rir(profile.targetRir.round());
    }();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    exercise.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!cardio) ...[
                    const SizedBox(height: 2),
                    Text(
                      _setNumber <= s.sets
                          ? 'Set $_setNumber of ${s.sets}'
                          : 'Extra set $_setNumber (plan was ${s.sets})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    [
                      exercise.primaryMuscleGroups
                          .map(muscleGroupLabel)
                          .join(', '),
                      ?s.equipmentLabel,
                    ].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.aiTip ?? s.reason,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!cardio) ...[
                        Expanded(
                          child: TextFormField(
                            controller: _weight,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Weight',
                              hintText: s.weight == null ? 'Bodyweight' : null,
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) return null;
                              final parsed = double.tryParse(text);
                              if (parsed == null || parsed < 0) {
                                return 'Enter a weight';
                              }
                              return parsed > 2000 ? 'Too heavy' : null;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<WeightUnit>(
                          segments: const [
                            ButtonSegment(
                              value: WeightUnit.lb,
                              label: Text('lb'),
                            ),
                            ButtonSegment(
                              value: WeightUnit.kg,
                              label: Text('kg'),
                            ),
                          ],
                          selected: {_unit},
                          showSelectedIcon: false,
                          onSelectionChanged: (v) =>
                              setState(() => _unit = v.first),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: TextFormField(
                          controller: _reps,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: cardio ? 'Minutes' : 'Reps',
                          ),
                          validator: (value) {
                            final parsed = int.tryParse(value?.trim() ?? '');
                            if (parsed == null || parsed < 1) return 'Required';
                            return parsed > 1000 ? 'Too many' : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  if (!cardio) ...[
                    const SizedBox(height: 16),
                    EffortSlider(
                      value: _effort!,
                      onChanged: (v) => setState(() => _effort = v),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving ? null : _log,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(cardio ? 'Log workout' : 'Log set $_setNumber'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
