import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/training/models.dart';
import '../../auth/domain/auth_validators.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/presentation/rest_timer.dart';
import '../data/profile_providers.dart';

/// Opens the one edit form for everything on the profile. Resolves to true
/// when something was saved.
Future<bool> showProfileEditSheet(
  BuildContext context,
  TrainingProfile profile,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: ProfileEditSheet(initial: profile),
    ),
  );
  return saved ?? false;
}

/// Display name, W-number, training preferences, effort, rest timer and
/// bodyweight - one form, one Save. The password is deliberately not here:
/// it has its own flow behind the profile menu (`change_password_sheet.dart`)
/// that asks for the current password first.
class ProfileEditSheet extends ConsumerStatefulWidget {
  const ProfileEditSheet({super.key, required this.initial});

  final TrainingProfile initial;

  @override
  ConsumerState<ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<ProfileEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late TrainingProfile _profile = widget.initial;
  late final _name = TextEditingController(
    text: widget.initial.displayName ?? '',
  );
  late final _wNumber = TextEditingController(
    text: widget.initial.wNumber ?? '',
  );
  late final _bodyweight = TextEditingController(
    text: widget.initial.bodyweightLb == null
        ? ''
        : formatTrimmed(
            roundToIncrement(
              widget.initial.unit.fromLb(widget.initial.bodyweightLb!),
              0.5,
            ),
          ),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _wNumber.dispose();
    _bodyweight.dispose();
    super.dispose();
  }

  void _update(TrainingProfile next) => setState(() => _profile = next);

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final bodyweightText = _bodyweight.text.trim();
    final updated = _profile.copyWith(
      displayName: _name.text.trim(),
      wNumber: () => normalizeWNumber(_wNumber.text),
      bodyweightLb: () => bodyweightText.isEmpty
          ? null
          : _profile.unit.toLb(double.parse(bodyweightText)),
    );
    try {
      await ref.read(profileActionsProvider).save(updated);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final extended = _profile.hasExtendedColumns;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: theme.textTheme.labelLarge),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Edit profile',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                        ),
                        validator: AuthValidators.displayName,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _wNumber,
                        enabled: extended,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp('[wW0-9]')),
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'W-Number',
                          hintText: 'W0123456',
                        ),
                        validator: (v) {
                          final w = normalizeWNumber(v);
                          if (w == null || kWNumberPattern.hasMatch(w)) {
                            return null;
                          }
                          return 'W followed by 7 digits';
                        },
                      ),
                      label('Goal'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final goal in TrainingGoal.values)
                            ChoiceChip(
                              label: Text(goal.label),
                              selected: _profile.goal == goal,
                              onSelected: (_) =>
                                  _update(_profile.copyWith(goal: goal)),
                            ),
                        ],
                      ),
                      label('Days per week'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var d = 3; d <= 7; d++)
                            ChoiceChip(
                              label: Text('$d'),
                              selected: _profile.daysPerWeek == d,
                              onSelected: (_) =>
                                  _update(_profile.copyWith(daysPerWeek: d)),
                            ),
                        ],
                      ),
                      if (extended) ...[
                        label('Experience'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final e in TrainingExperience.values)
                              ChoiceChip(
                                label: Text(e.label),
                                tooltip: e.description,
                                selected: _profile.experience == e,
                                onSelected: (_) =>
                                    _update(_profile.copyWith(experience: e)),
                              ),
                          ],
                        ),
                      ],
                      label('Weight unit'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final unit in WeightUnit.values)
                            ChoiceChip(
                              label: Text(unit == WeightUnit.lb ? 'lb' : 'kg'),
                              selected: _profile.unit == unit,
                              onSelected: (_) => _changeUnit(unit),
                            ),
                        ],
                      ),
                      label('Rate effort with'),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (scale, text) in const [
                            (EffortScale.rpe, 'RPE (exertion, 1-10)'),
                            (EffortScale.rir, 'RIR (reps left)'),
                          ])
                            ChoiceChip(
                              label: Text(text),
                              selected: _profile.effortScale == scale,
                              onSelected: (_) => _update(
                                _profile.copyWith(effortScale: scale),
                              ),
                            ),
                        ],
                      ),
                      if (extended) ...[
                        label('How hard working sets should feel'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final rpe in kTargetRpeChoices)
                              ChoiceChip(
                                label: Text(
                                  targetEffortLabel(rpe, _profile.effortScale),
                                ),
                                selected: _profile.targetRpe == rpe,
                                onSelected: (_) =>
                                    _update(_profile.copyWith(targetRpe: rpe)),
                              ),
                          ],
                        ),
                        label(
                          'Rest timer · '
                          '${formatRest(Duration(seconds: _profile.restTimerSeconds))}',
                        ),
                        Slider(
                          min: 15,
                          max: 300,
                          divisions: (300 - 15) ~/ 15,
                          value: _profile.restTimerSeconds
                              .clamp(15, 300)
                              .toDouble(),
                          label: formatRest(
                            Duration(seconds: _profile.restTimerSeconds),
                          ),
                          onChanged: (v) => _update(
                            _profile.copyWith(restTimerSeconds: v.round()),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _bodyweight,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Bodyweight (optional)',
                            suffixText: _profile.unit.wireName,
                            helperText:
                                'Only used to estimate starting weights.',
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return null;
                            final parsed = double.tryParse(t);
                            if (parsed == null) return 'Enter a number';
                            final lb = _profile.unit.toLb(parsed);
                            return lb < 50 || lb > 700
                                ? 'That looks off - check the unit'
                                : null;
                          },
                        ),
                      ],
                      if (!extended) ...[
                        const SizedBox(height: 20),
                        Text(
                          'W-Number, experience, target effort, rest timer and '
                          'bodyweight unlock once the database is updated '
                          '(migration 0009).',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(_error!, style: TextStyle(color: scheme.error)),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save'),
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

  /// Keeps the typed bodyweight the same physical weight across a unit flip.
  void _changeUnit(WeightUnit unit) {
    if (unit == _profile.unit) return;
    final parsed = double.tryParse(_bodyweight.text.trim());
    if (parsed != null) {
      final converted = unit.fromLb(_profile.unit.toLb(parsed));
      _bodyweight.text = formatTrimmed(roundToIncrement(converted, 0.5));
    }
    _update(_profile.copyWith(unit: unit));
  }
}
