import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/domain/training_profile.dart';
import '../data/profile_providers.dart';

/// "This week's plan" -> Change: only what shapes the plan - the goal and
/// the days per week. Everything else about the account lives on the
/// profile.
Future<void> showPlanSettingsSheet(
  BuildContext context,
  TrainingProfile profile,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => PlanSettingsSheet(initial: profile),
);

class PlanSettingsSheet extends ConsumerStatefulWidget {
  const PlanSettingsSheet({super.key, required this.initial});

  final TrainingProfile initial;

  @override
  ConsumerState<PlanSettingsSheet> createState() => _PlanSettingsSheetState();
}

class _PlanSettingsSheetState extends ConsumerState<PlanSettingsSheet> {
  late TrainingProfile _profile = widget.initial;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileActionsProvider).save(_profile);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your plan',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Text('Goal', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final goal in TrainingGoal.values)
                    ChoiceChip(
                      label: Text(goal.label),
                      selected: _profile.goal == goal,
                      onSelected: (_) => setState(
                        () => _profile = _profile.copyWith(goal: goal),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Days per week', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var d = 3; d <= 7; d++)
                    ChoiceChip(
                      label: Text('$d'),
                      selected: _profile.daysPerWeek == d,
                      onSelected: (_) => setState(
                        () => _profile = _profile.copyWith(daysPerWeek: d),
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
