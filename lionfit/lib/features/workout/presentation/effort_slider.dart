import 'package:flutter/material.dart';

import '../../../core/training/models.dart';
import '../domain/training_profile.dart';

/// What the lifter said about a set's effort: nothing, an RPE, or an RIR.
@immutable
final class EffortEntry {
  const EffortEntry.none() : scale = null, rpe = null, rir = null;
  const EffortEntry.rpe(double this.rpe) : scale = EffortScale.rpe, rir = null;
  const EffortEntry.rir(int this.rir) : scale = EffortScale.rir, rpe = null;

  factory EffortEntry.fromSet({double? rpe, int? rir}) => rpe != null
      ? EffortEntry.rpe(rpe)
      : rir != null
      ? EffortEntry.rir(rir)
      : const EffortEntry.none();

  /// The starting point when the lifter turns rating on.
  factory EffortEntry.defaultFor(EffortScale scale) => scale == EffortScale.rpe
      ? const EffortEntry.rpe(8)
      : const EffortEntry.rir(2);

  final EffortScale? scale;
  final double? rpe;
  final int? rir;
}

/// RPE runs 5-10 in half points; below 5 is a warm-up and not worth rating.
const double kRpeMin = 5;
const double kRpeMax = 10;

/// RIR runs 0-5; the top stop means "5 or more" and is stored as 5.
const int kRirMax = 5;

String rpeMeaning(double rpe) => switch (rpe) {
  >= 10 => 'Max effort - nothing left',
  >= 9.5 => 'Maybe one more rep',
  >= 9 => 'One rep left',
  >= 8.5 => 'One, maybe two left',
  >= 8 => 'Two reps left',
  >= 7.5 => 'Two or three left',
  >= 7 => 'Three reps left',
  >= 6 => 'Four or more left',
  _ => 'Easy - plenty left',
};

String rirMeaning(int rir) => switch (rir) {
  0 => 'Could not do another rep',
  1 => 'One more rep was there',
  >= kRirMax => '$kRirMax or more reps left - pretty easy',
  _ => '$rir more reps were there',
};

/// Skip / RPE / RIR toggle with a slider, replacing the number box.
///
/// A slider makes the common case one drag, and the caption under it says in
/// plain words what the number means, so nobody has to know the scale.
class EffortSlider extends StatelessWidget {
  const EffortSlider({super.key, required this.value, required this.onChanged});

  final EffortEntry value;
  final ValueChanged<EffortEntry> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = value.scale;

    // Chips, not a SegmentedButton: chips wrap at large text sizes, a
    // segmented control just overflows.
    void select(EffortScale? next) => onChanged(
      next == null ? const EffortEntry.none() : EffortEntry.defaultFor(next),
    );
    final toggle = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (option, label) in const [
          (null, 'Skip'),
          (EffortScale.rpe, 'RPE'),
          (EffortScale.rir, 'RIR'),
        ])
          ChoiceChip(
            label: Text(label),
            selected: scale == option,
            onSelected: (_) => select(option),
          ),
      ],
    );

    if (scale == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How hard was it?', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          toggle,
        ],
      );
    }

    final isRpe = scale == EffortScale.rpe;
    final number = isRpe
        ? 'RPE ${formatTrimmed(value.rpe!)}'
        : value.rir! >= kRirMax
        ? '$kRirMax+ RIR'
        : '${value.rir} RIR';
    final meaning = isRpe ? rpeMeaning(value.rpe!) : rirMeaning(value.rir!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'How hard was it?',
                style: theme.textTheme.labelLarge,
              ),
            ),
            Text(
              number,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        toggle,
        Semantics(
          label: isRpe ? 'Rate of perceived exertion' : 'Reps in reserve',
          value: '$number. $meaning',
          child: Slider(
            min: isRpe ? kRpeMin : 0,
            max: isRpe ? kRpeMax : kRirMax.toDouble(),
            divisions: isRpe ? ((kRpeMax - kRpeMin) * 2).round() : kRirMax,
            // Clamped: sets logged with the old free-text box can hold RPE
            // below 5 or RIR above 5.
            value: isRpe
                ? value.rpe!.clamp(kRpeMin, kRpeMax)
                : value.rir!.clamp(0, kRirMax).toDouble(),
            label: number,
            onChanged: (v) => onChanged(
              isRpe
                  ? EffortEntry.rpe((v * 2).round() / 2)
                  : EffortEntry.rir(v.round()),
            ),
          ),
        ),
        Text(
          meaning,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
