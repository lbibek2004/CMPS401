/// The user's row in `profiles`: name, preferences, and the onboarding survey
/// answers. Every field has the same default as the database column, so a
/// profile that failed to load still yields a working app.
library;

import '../../../core/training/models.dart';

enum TrainingGoal {
  weightLoss('weight_loss', 'Weight loss'),
  muscleGain('muscle_gain', 'Muscle gain'),
  generalFitness('general_fitness', 'General fitness');

  const TrainingGoal(this.wireName, this.label);

  final String wireName;
  final String label;

  static TrainingGoal fromWire(String? wire) => values.firstWhere(
    (goal) => goal.wireName == wire,
    orElse: () => TrainingGoal.generalFitness,
  );
}

enum EffortScale {
  rpe('rpe'),
  rir('rir');

  const EffortScale(this.wireName);

  final String wireName;
}

/// How long the user has been lifting - the survey's main calibration input.
enum TrainingExperience {
  brandNew('new', 'Brand new', 'Never lifted, or not in over a year'),
  beginner('beginner', 'Getting started', 'Lifting for under 6 months'),
  intermediate('intermediate', 'Consistent', '6 months to 2 years'),
  advanced('advanced', 'Experienced', '2+ years of steady training');

  const TrainingExperience(this.wireName, this.label, this.description);

  final String wireName;
  final String label;
  final String description;

  static TrainingExperience? fromWire(String? wire) {
    for (final value in values) {
      if (value.wireName == wire) return value;
    }
    return null;
  }
}

enum ThemePreference {
  system('system', 'Match device'),
  light('light', 'Light'),
  dark('dark', 'Dark');

  const ThemePreference(this.wireName, this.label);

  final String wireName;
  final String label;

  static ThemePreference fromWire(String? wire) => values.firstWhere(
    (value) => value.wireName == wire,
    orElse: () => ThemePreference.system,
  );
}

/// The three effort targets the survey and profile offer, on the RPE scale.
/// RIR is `10 - rpe`.
const kTargetRpeChoices = <double>[7, 8, 9];

String targetEffortLabel(double rpe, EffortScale scale) {
  final rir = (10 - rpe).round();
  final name = switch (rpe) {
    <= 7 => 'Comfortable',
    <= 8 => 'Challenging',
    _ => 'Near max',
  };
  return scale == EffortScale.rpe
      ? '$name · RPE ${formatTrimmed(rpe)}'
      : '$name · $rir RIR';
}

/// "W" + 7 digits, the Southeastern student ID format. Same check as the
/// `profiles_w_number_format` constraint.
final RegExp kWNumberPattern = RegExp(r'^W[0-9]{7}$');

/// Uppercases and trims; returns null for blank input.
String? normalizeWNumber(String? raw) {
  final value = raw?.trim().toUpperCase() ?? '';
  return value.isEmpty ? null : value;
}

final class TrainingProfile {
  const TrainingProfile({
    this.goal = TrainingGoal.generalFitness,
    this.daysPerWeek = 3,
    this.unit = WeightUnit.lb,
    this.effortScale = EffortScale.rpe,
    this.displayName,
    this.wNumber,
    this.experience,
    this.targetRpe = 8,
    this.bodyweightLb,
    this.restTimerSeconds = 90,
    this.themePreference = ThemePreference.system,
    this.onboardingCompletedAt,
    this.hasExtendedColumns = false,
    this.isAdmin = false,
  });

  factory TrainingProfile.fromRow(Map<String, dynamic> row) => TrainingProfile(
    goal: TrainingGoal.fromWire(row['goal'] as String?),
    daysPerWeek: ((row['days_per_week'] as num?)?.toInt() ?? 3).clamp(3, 7),
    unit: (row['unit_preference'] as String?) == 'kg'
        ? WeightUnit.kg
        : WeightUnit.lb,
    effortScale: (row['effort_preference'] as String?) == 'rir'
        ? EffortScale.rir
        : EffortScale.rpe,
    displayName: row['display_name'] as String?,
    wNumber: row['w_number'] as String?,
    experience: TrainingExperience.fromWire(row['experience'] as String?),
    targetRpe: ((row['target_rpe'] as num?)?.toDouble() ?? 8).clamp(6, 10),
    bodyweightLb: (row['bodyweight_lb'] as num?)?.toDouble(),
    restTimerSeconds: ((row['rest_timer_seconds'] as num?)?.toInt() ?? 90)
        .clamp(15, 600),
    themePreference: ThemePreference.fromWire(
      row['theme_preference'] as String?,
    ),
    onboardingCompletedAt: row['onboarding_completed_at'] == null
        ? null
        : DateTime.tryParse(row['onboarding_completed_at'] as String),
    // Migration 0009 adds these columns. Without it the key is absent from a
    // select(*) row, and the survey/profile settings are switched off rather
    // than failing on save.
    hasExtendedColumns: row.containsKey('onboarding_completed_at'),
    isAdmin: row['role'] == 'admin',
  );

  final TrainingGoal goal;

  /// 3-7, the same check constraint as the column.
  final int daysPerWeek;
  final WeightUnit unit;
  final EffortScale effortScale;

  final String? displayName;
  final String? wNumber;

  /// Null until the survey is answered.
  final TrainingExperience? experience;

  /// How hard working sets should be, on the RPE scale (6-10).
  final double targetRpe;

  /// Optional; only used to estimate first-session loads.
  final double? bodyweightLb;
  final int restTimerSeconds;
  final ThemePreference themePreference;
  final DateTime? onboardingCompletedAt;

  /// True when the database has migration 0009's columns.
  final bool hasExtendedColumns;

  /// `profiles.role = 'admin'`. Read-only here: [toRow] never sends the role,
  /// and the database refuses a client write to it anyway (migration 0002).
  /// This only decides what the app *shows*; what an admin may *change* is
  /// enforced by RLS through `is_admin()`.
  final bool isAdmin;

  double get targetRir => (10 - targetRpe).clamp(0, 4).toDouble();

  /// The survey is owed. False when the columns do not exist yet, so nobody
  /// is sent to a survey that cannot be saved.
  bool get needsOnboarding =>
      hasExtendedColumns && onboardingCompletedAt == null;

  /// The writable columns. Migration 0002 grants UPDATE on the first five;
  /// 0009 grants the rest, so they are only sent when the database has them.
  Map<String, dynamic> toRow() => {
    'goal': goal.wireName,
    'days_per_week': daysPerWeek,
    'unit_preference': unit.wireName,
    'effort_preference': effortScale.wireName,
    if (displayName != null && displayName!.trim().isNotEmpty)
      'display_name': displayName!.trim(),
    if (hasExtendedColumns) ...{
      'w_number': wNumber,
      'experience': experience?.wireName,
      'target_rpe': targetRpe,
      'bodyweight_lb': bodyweightLb,
      'rest_timer_seconds': restTimerSeconds,
      'theme_preference': themePreference.wireName,
      'onboarding_completed_at': onboardingCompletedAt
          ?.toUtc()
          .toIso8601String(),
    },
  };

  TrainingProfile copyWith({
    TrainingGoal? goal,
    int? daysPerWeek,
    WeightUnit? unit,
    EffortScale? effortScale,
    String? displayName,
    String? Function()? wNumber,
    TrainingExperience? experience,
    double? targetRpe,
    double? Function()? bodyweightLb,
    int? restTimerSeconds,
    ThemePreference? themePreference,
    DateTime? onboardingCompletedAt,
  }) => TrainingProfile(
    goal: goal ?? this.goal,
    daysPerWeek: daysPerWeek ?? this.daysPerWeek,
    unit: unit ?? this.unit,
    effortScale: effortScale ?? this.effortScale,
    displayName: displayName ?? this.displayName,
    wNumber: wNumber == null ? this.wNumber : wNumber(),
    experience: experience ?? this.experience,
    targetRpe: targetRpe ?? this.targetRpe,
    bodyweightLb: bodyweightLb == null ? this.bodyweightLb : bodyweightLb(),
    restTimerSeconds: restTimerSeconds ?? this.restTimerSeconds,
    themePreference: themePreference ?? this.themePreference,
    onboardingCompletedAt: onboardingCompletedAt ?? this.onboardingCompletedAt,
    hasExtendedColumns: hasExtendedColumns,
    isAdmin: isAdmin,
  );
}

/// One survey answer: "I can do [reps] at [weight] on this exercise".
final class StrengthBaseline {
  const StrengthBaseline({
    required this.exerciseId,
    required this.weight,
    required this.unit,
    required this.reps,
    this.recordedAt,
  });

  factory StrengthBaseline.fromRow(Map<String, dynamic> row) =>
      StrengthBaseline(
        exerciseId: row['exercise_id'] as String,
        weight: (row['weight'] as num).toDouble(),
        unit: (row['unit'] as String?) == 'kg' ? WeightUnit.kg : WeightUnit.lb,
        reps: (row['reps'] as num).toInt(),
        recordedAt: row['updated_at'] == null
            ? null
            : DateTime.tryParse(row['updated_at'] as String)?.toLocal(),
      );

  final String exerciseId;
  final double weight;
  final WeightUnit unit;
  final int reps;

  /// When the survey answer was given. Null means "just now" (not saved yet).
  final DateTime? recordedAt;

  double get weightLb => unit.toLb(weight);

  Map<String, dynamic> toRow(String userId) => {
    'user_id': userId,
    'exercise_id': exerciseId,
    'weight': weight,
    'unit': unit.wireName,
    'reps': reps,
  };
}

/// "Replace this exercise" on one plan day.
final class PlanSwap {
  const PlanSwap({
    required this.planDate,
    required this.originalExerciseId,
    required this.replacementExerciseId,
  });

  factory PlanSwap.fromRow(Map<String, dynamic> row) => PlanSwap(
    planDate: _parseDate(row['plan_date'] as String),
    originalExerciseId: row['original_exercise_id'] as String,
    replacementExerciseId: row['replacement_exercise_id'] as String,
  );

  final DateTime planDate;
  final String originalExerciseId;
  final String replacementExerciseId;

  static DateTime _parseDate(String value) {
    final parts = value.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }
}
