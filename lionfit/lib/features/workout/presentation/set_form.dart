import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/training/models.dart';
import '../domain/workout_models.dart';
import 'effort_slider.dart';

/// Starting values for a [SetForm].
final class SetDraft {
  const SetDraft({
    this.weight,
    this.unit = WeightUnit.lb,
    this.reps,
    this.setType = SetType.working,
    this.effort = const EffortEntry.none(),
  });

  factory SetDraft.fromSet(SetRecord set) => SetDraft(
    weight: set.weight,
    unit: set.unit,
    reps: set.reps,
    setType: set.setType,
    effort: EffortEntry.fromSet(rpe: set.rpe, rir: set.rir),
  );

  final double? weight;
  final WeightUnit unit;
  final int? reps;
  final SetType setType;
  final EffortEntry effort;
}

/// Weight + unit, reps, set type and the effort slider - one set's fields.
///
/// Used twice: to log a new set (it keeps every field after submit, because
/// the next set is usually the same) and to edit a logged one.
class SetForm extends StatefulWidget {
  const SetForm({
    super.key,
    required this.exercise,
    required this.initial,
    required this.onSubmit,
    required this.submitLabel,
    this.onCancel,
  });

  final CatalogExercise exercise;
  final SetDraft initial;

  /// Throws to keep the form as it is and let the caller show the error.
  final Future<void> Function(NewSet set) onSubmit;
  final String submitLabel;
  final VoidCallback? onCancel;

  @override
  State<SetForm> createState() => _SetFormState();
}

class _SetFormState extends State<SetForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  late WeightUnit _unit;
  late SetType _setType;
  late EffortEntry _effort;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _weight = TextEditingController(
      text: initial.weight == null || initial.weight == 0
          ? ''
          : formatTrimmed(initial.weight!),
    );
    _reps = TextEditingController(text: initial.reps?.toString() ?? '');
    _unit = initial.unit;
    _setType = initial.setType;
    _effort = initial.effort;
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final weightText = _weight.text.trim();
    try {
      await widget.onSubmit(
        NewSet(
          exerciseId: widget.exercise.id,
          setType: _setType,
          unit: _unit,
          weight: weightText.isEmpty ? null : double.parse(weightText),
          reps: int.parse(_reps.text.trim()),
          rpe: _effort.rpe,
          rir: _effort.rir,
        ),
      );
    } catch (_) {
      // The caller showed the error; keep the input.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    if (parsed == null || parsed < 1) {
      return widget.exercise.isCardio ? 'Minutes' : 'Reps';
    }
    if (parsed > 1000) return 'Too many';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cardio = widget.exercise.isCardio;
    final weightField = TextFormField(
      controller: _weight,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
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
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: cardio ? 'Minutes' : 'Reps',
        isDense: true,
      ),
      validator: _validateReps,
      onFieldSubmitted: (_) => _submit(),
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
    final effort = EffortSlider(
      value: _effort,
      onChanged: (value) => setState(() => _effort = value),
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
      label: Text(widget.submitLabel),
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (widget.onCancel != null)
          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        submit,
      ],
    );

    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          final loadRow = cardio
              ? repsField
              : wide
              ? Row(
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
                )
              : Column(
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: repsField),
                        const SizedBox(width: 12),
                        Expanded(child: typeMenu),
                      ],
                    ),
                  ],
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              loadRow,
              if (!cardio) ...[const SizedBox(height: 12), effort],
              const SizedBox(height: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}
