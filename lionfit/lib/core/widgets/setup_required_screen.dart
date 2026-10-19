import 'package:flutter/material.dart';

/// Shown when the app cannot reach Supabase because configuration is missing.
///
/// This exists so `flutter run` always produces something readable instead of
/// a red screen or a silent hang. It names the actual problem and the fix.
class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({required this.problem, super.key});

  final String problem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Configuration needed',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(problem, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    'flutter run -d chrome --dart-define-from-file=.env',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Copy .env.example to .env and fill in your Supabase project URL '
                  'and publishable (anon) key.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
