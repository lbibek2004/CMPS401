import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/lionfit_tokens.dart';
import '../../../core/training/models.dart';
import '../../home/domain/home_greeting.dart';
import '../../workout/data/workout_repository.dart';
import '../../workout/domain/training_profile.dart';
import '../../workout/presentation/rest_timer.dart';
import '../../admin/presentation/admin_screen.dart' show AdminBadge;
import '../data/profile_providers.dart';
import 'change_password_sheet.dart';
import 'profile_edit_sheet.dart';

/// `/profile` - who you are and how the app is set up for you. Read-only:
/// every change goes through the one Edit in [ProfileMenuButton].
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profileAsync = ref.watch(trainingProfileProvider);
    final email = accountEmailFor(ref.watch(sessionProvider));

    return Scaffold(
      body: profileAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(trainingProfileProvider),
            child: const Text('Could not load your profile. Try again'),
          ),
        ),
        data: (p) {
          final name = p.displayName?.trim().isNotEmpty == true
              ? p.displayName!.trim()
              : (email ?? 'Lion');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            child: Text(
                              _initials(name),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (p.isAdmin) ...[
                                  const SizedBox(height: 4),
                                  const AdminBadge(),
                                ],
                                if (email != null)
                                  Text(
                                    email,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (p.isAdmin) ...[
                        OutlinedButton.icon(
                          onPressed: () => context.go(Routes.admin),
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          label: const Text('Admin tools'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _Group(
                        title: 'Account',
                        rows: [('W-Number', p.wNumber ?? 'Not set')],
                      ),
                      _Group(
                        title: 'Training',
                        rows: [
                          ('Goal', p.goal.label),
                          ('Days per week', '${p.daysPerWeek}'),
                          if (p.hasExtendedColumns)
                            ('Experience', p.experience?.label ?? 'Not set'),
                          if (p.bodyweightLb != null)
                            (
                              'Bodyweight',
                              '${formatTrimmed(roundToIncrement(p.unit.fromLb(p.bodyweightLb!), 0.5))} '
                                  '${p.unit.wireName}',
                            ),
                        ],
                      ),
                      _Group(
                        title: 'Logging',
                        rows: [
                          ('Weight unit', p.unit.wireName),
                          (
                            'Effort',
                            p.effortScale == EffortScale.rpe
                                ? 'RPE (exertion)'
                                : 'RIR (reps in reserve)',
                          ),
                          if (p.hasExtendedColumns) ...[
                            (
                              'Target effort',
                              targetEffortLabel(p.targetRpe, p.effortScale),
                            ),
                            (
                              'Rest timer',
                              formatRest(Duration(seconds: p.restTimerSeconds)),
                            ),
                          ],
                        ],
                      ),
                      _Group(
                        title: 'Appearance',
                        rows: [
                          (
                            'Theme',
                            (ref.watch(themeOverrideProvider) ??
                                    p.themePreference)
                                .label,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .split(RegExp(r'[\s@._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final second = parts.length > 1 ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(
            LionFitTokens.of(context).radiusLg,
          ),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyLarge),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _MenuAction { edit, survey, theme, password, admin, logOut }

/// The hamburger at the top right of the profile tab: Edit profile, Retake
/// survey, Change theme, Change password, Admin tools (admins only), Log out.
/// The password sits here, out of the way, and not in the everyday edit form.
class ProfileMenuButton extends ConsumerWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Profile menu',
      icon: const Icon(Icons.menu),
      onSelected: (action) => switch (action) {
        _MenuAction.edit => _edit(context, ref),
        _MenuAction.survey => context.go(Routes.welcome),
        _MenuAction.theme => _pickTheme(context, ref),
        _MenuAction.password => _changePassword(context),
        _MenuAction.admin => context.go(Routes.admin),
        _MenuAction.logOut => _logOut(context, ref),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _MenuAction.edit,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit profile'),
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.survey,
          child: ListTile(
            leading: Icon(Icons.quiz_outlined),
            title: Text('Retake survey'),
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.theme,
          child: ListTile(
            leading: Icon(Icons.brightness_6_outlined),
            title: Text('Change theme'),
          ),
        ),
        const PopupMenuItem(
          value: _MenuAction.password,
          child: ListTile(
            leading: Icon(Icons.lock_reset),
            title: Text('Change password'),
          ),
        ),
        if (ref.read(trainingProfileProvider).value?.isAdmin ?? false)
          const PopupMenuItem(
            value: _MenuAction.admin,
            child: ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Admin tools'),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _MenuAction.logOut,
          child: ListTile(leading: Icon(Icons.logout), title: Text('Log out')),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final profile = await ref.read(trainingProfileProvider.future);
    if (!context.mounted) return;
    final saved = await showProfileEditSheet(context, profile);
    if (saved && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile saved.')));
    }
  }

  Future<void> _changePassword(BuildContext context) async {
    final changed = await showChangePasswordSheet(context);
    if (changed && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password updated.')));
    }
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final profile = await ref.read(trainingProfileProvider.future);
    if (!context.mounted) return;
    final current = ref.read(themeOverrideProvider) ?? profile.themePreference;
    final picked = await showDialog<ThemePreference>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final option in ThemePreference.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option),
              child: Row(
                children: [
                  Icon(
                    option == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Text(option.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await ref.read(profileActionsProvider).setTheme(profile, picked);
  }

  Future<void> _logOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authControllerProvider).signOut();
      // The router's auth listener would redirect anyway; going to the
      // landing page explicitly makes the destination obvious.
      if (context.mounted) context.go(Routes.landing);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is AuthFailure
                ? error.message
                : 'Could not log out. Please try again.',
          ),
        ),
      );
    }
  }
}
