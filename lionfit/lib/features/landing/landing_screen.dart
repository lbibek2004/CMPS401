import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';

/// Public marketing page at `/`.
///
/// Deliberately plain: flat theme colors, one column, no gradients and no
/// decoration that is not carrying information. It is expected to be
/// redesigned once the design system lands, so there is nothing here to
/// unwind.
class LandingScreen extends ConsumerWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideBreakpoint;
            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 48 : 24,
                      vertical: wide ? 28 : 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _TopBar(),
                        SizedBox(height: wide ? 104 : 56),
                        _Hero(wide: wide),
                        SizedBox(height: wide ? 120 : 72),
                        _WhatItDoes(wide: wide),
                        SizedBox(height: wide ? 96 : 64),
                        const _Footer(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Past this width the page uses the two-column feature list and the larger
/// display type. Below it everything stacks.
const double _wideBreakpoint = 840;

/// Text is never allowed to run the full width of a desktop monitor.
const double _maxContentWidth = 1040;
const double _maxHeadlineWidth = 760;
const double _maxProseWidth = 620;

/// Tap targets: Material 3 buttons default to 40dp, which is under the 48dp
/// accessibility floor.
const Size _ctaMinimumSize = Size(0, 52);

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Wrap, not Row: at a 200% text scale on a narrow phone these two land on
    // separate lines instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(
          'LionFit',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        TextButton(
          onPressed: () => context.go(Routes.login),
          style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headlineStyle =
        (wide ? theme.textTheme.displayMedium : theme.textTheme.headlineMedium)
            ?.copyWith(fontWeight: FontWeight.w700, height: 1.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SOUTHEASTERN LOUISIANA UNIVERSITY',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxHeadlineWidth),
          child: Text(
            'Train with what the Rec Center actually has.',
            style: headlineStyle,
          ),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxProseWidth),
          child: Text(
            'LionFit plans your week around the equipment on the floor at the '
            'Pennington Student Activity Center, logs every set you lift, and '
            'reads your own history to pick the next load.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 40),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: () => context.go(Routes.signUp),
              style: FilledButton.styleFrom(
                minimumSize: _ctaMinimumSize,
                padding: const EdgeInsets.symmetric(horizontal: 28),
              ),
              child: const Text('Create an account'),
            ),
            OutlinedButton(
              onPressed: () => context.go(Routes.login),
              style: OutlinedButton.styleFrom(
                minimumSize: _ctaMinimumSize,
                padding: const EdgeInsets.symmetric(horizontal: 28),
              ),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Four concrete statements, as a definition list rather than a card grid.
class _WhatItDoes extends StatelessWidget {
  const _WhatItDoes({required this.wide});

  final bool wide;

  static const _entries = <(String, String)>[
    (
      'Plans around real equipment',
      'Your week is built from what Pennington actually stocks, so you are '
          'not improvising around a machine the app assumed was free.',
    ),
    (
      'Logs sets the way you lift',
      'Weight in pounds or kilos, reps, set type, and RPE or RIR — warm-ups, '
          'drop sets and supersets included.',
    ),
    (
      'Picks the next load from your history',
      'Bench 135 for ten and finish strong, and the next session asks for '
          'more. Miss the last rep and it backs the weight off.',
    ),
    (
      'Shows what you trained in 3D',
      'An anatomy model colors the muscle groups you hit over the last 1 to '
          '30 days, so the gaps are obvious.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'WHAT IT DOES',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        for (final (label, body) in _entries) ...[
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: wide ? 28 : 22),
            child: _Entry(label: label, body: body, wide: wide),
          ),
        ],
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.label, required this.body, required this.wide});

  final String label;
  final String body;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final bodyText = Text(
      body,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [labelText, const SizedBox(height: 8), bodyText],
      );
    }
    // Flex rather than a fixed label column so the split still holds when the
    // user scales text up.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(flex: 2, child: labelText),
        const SizedBox(width: 32),
        Flexible(flex: 5, child: bodyText),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'LionFit is a student project at Southeastern Louisiana University. '
      'Plans are built from the equipment inventory at the Pennington Student '
      'Activity Center.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    );
  }
}
