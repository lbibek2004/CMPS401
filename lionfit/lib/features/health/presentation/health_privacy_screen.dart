import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../application/health_controller.dart';
import '../domain/health_models.dart';

/// `/health-privacy`: what LionFit does with Health Connect data.
///
/// Health Connect links here from its permission screen ("Read privacy
/// policy") - Android requires every app that asks for health permissions
/// to have one. MainActivity.kt opens this route for those intents, which is
/// why it is reachable signed out and before the survey.
class HealthPrivacyScreen extends ConsumerWidget {
  const HealthPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Only where Health Connect is installed and usable.
    final canManage = switch (ref.watch(healthProvider).value) {
      HealthReady() || HealthNeedsAccess() => true,
      _ => false,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health data and privacy'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          // Opened from Health Connect there is nothing to go back to.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.landing),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'LionFit can show your steps and heart rate next to your '
                  'training. It gets them from Health Connect, only if you '
                  'allow it.',
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
                const _Section(
                  icon: Icons.visibility_outlined,
                  title: 'What LionFit reads',
                  body:
                      'Steps, heart rate, and resting heart rate. Nothing '
                      'else - not sleep, location, or any other health '
                      'record. You choose each one on Health Connect\'s '
                      'permission screen and can allow some and not others.',
                ),
                const _Section(
                  icon: Icons.insights_outlined,
                  title: 'What it is used for',
                  body:
                      "Only to show today's numbers on your Home screen. "
                      'It is not used for advertising, and it does not '
                      'change your workout plan.',
                ),
                const _Section(
                  icon: Icons.phone_android,
                  title: 'Where it goes',
                  body:
                      'It stays on this phone. LionFit reads it while the app '
                      'is open, does not upload it to its servers, and does '
                      'not share or sell it. Your LionFit account and the '
                      'app admins never see it.',
                ),
                const _Section(
                  icon: Icons.lock_outline,
                  title: 'What LionFit cannot do',
                  body:
                      'Write, change, or delete anything in Health Connect. '
                      'Its access is read-only.',
                ),
                const _Section(
                  icon: Icons.toggle_off_outlined,
                  title: 'How to stop',
                  body:
                      'Open Health Connect, go to App permissions, choose '
                      'LionFit, and turn access off. Uninstalling LionFit '
                      'removes its access too.',
                ),
                if (canManage) ...[
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(healthProvider.notifier).openSettings(),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Health Connect'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
