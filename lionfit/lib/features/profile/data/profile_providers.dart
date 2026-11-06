import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../coach/data/coach_providers.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/training_profile.dart';

/// A theme picked in this session. Applied at once, before (and even if) the
/// save to `profiles.theme_preference` lands.
class ThemeOverrideController extends Notifier<ThemePreference?> {
  /// Cleared when the signed-in account changes, so one person's pick does
  /// not follow the next sign-in on a shared device.
  @override
  ThemePreference? build() {
    ref.watch(sessionProvider.select((session) => session?.user.id));
    return null;
  }

  void set(ThemePreference value) => state = value;
}

final themeOverrideProvider =
    NotifierProvider<ThemeOverrideController, ThemePreference?>(
      ThemeOverrideController.new,
    );

ThemeMode themeModeFor(ThemePreference preference) => switch (preference) {
  ThemePreference.system => ThemeMode.system,
  ThemePreference.light => ThemeMode.light,
  ThemePreference.dark => ThemeMode.dark,
};

/// What `MaterialApp.themeMode` uses: this session's pick, else the saved
/// preference, else the device setting.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final picked = ref.watch(themeOverrideProvider);
  final saved = ref.watch(trainingProfileProvider).value?.themePreference;
  return themeModeFor(picked ?? saved ?? ThemePreference.system);
});

/// Profile writes the screens share.
class ProfileActions {
  ProfileActions(this._ref);

  final Ref _ref;

  /// Saves [profile] and refreshes everything computed from it (the plan, the
  /// coach, the router's onboarding check).
  Future<void> save(TrainingProfile profile) async {
    await _ref.read(workoutRepositoryProvider).updateProfile(profile);
    _ref.invalidate(trainingProfileProvider);
  }

  /// Applies [preference] now and saves it when the database can hold it.
  Future<void> setTheme(
    TrainingProfile profile,
    ThemePreference preference,
  ) async {
    _ref.read(themeOverrideProvider.notifier).set(preference);
    if (!profile.hasExtendedColumns) return;
    try {
      await save(profile.copyWith(themePreference: preference));
    } catch (error) {
      debugPrint('theme preference not saved: $error');
    }
  }

  /// Saves the survey: profile answers, then the strength baselines, then the
  /// completion stamp - so a failure part-way leaves the survey still owed.
  ///
  /// Returns only once the **reloaded** profile says the survey is done. The
  /// router decides "survey owed?" from that provider, so navigating while it
  /// still held the old row bounced the user straight back to /welcome with
  /// the button spinning. Throws [ProfileNotSaved] if the reload still owes
  /// it, rather than leaving the caller to wait forever.
  Future<void> completeOnboarding(
    TrainingProfile answers,
    List<StrengthBaseline> baselines,
  ) async {
    final repo = _ref.read(workoutRepositoryProvider);
    await repo.updateProfile(answers);
    await repo.replaceBaselines(baselines);
    await repo.updateProfile(
      answers.copyWith(onboardingCompletedAt: DateTime.now()),
    );
    _ref.invalidate(strengthBaselinesProvider);
    _ref.invalidate(coachEngineProvider);
    final saved = await _ref.refresh(trainingProfileProvider.future);
    if (saved.needsOnboarding) throw const ProfileNotSaved();
  }
}

final profileActionsProvider = Provider<ProfileActions>(ProfileActions.new);
