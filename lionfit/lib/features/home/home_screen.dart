import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../health/presentation/health_card.dart';
import '../workout/data/workout_repository.dart';
import 'domain/home_greeting.dart';
import 'presentation/coach_section.dart';
import 'presentation/plan_section.dart';
import 'presentation/progress_section.dart';

/// The signed-in landing spot at `/home`.
///
/// The week's plan, progress and next loads are on the page itself rather
/// than behind a tap: this is the screen a student opens at the Rec Center
/// door, and the first question is "what am I doing today?". Getting to the
/// logger, history, map and profile is the shell's navigation bar.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Null when the session has not restored yet, or when Supabase is not
    // configured at all. Both render fine; nothing below dereferences it.
    final session = ref.watch(sessionProvider);
    final profileName = ref.watch(trainingProfileProvider).value?.displayName;
    final name = (profileName != null && profileName.trim().isNotEmpty)
        ? profileName.trim()
        : greetingNameFor(session);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;
          const gap = SizedBox(height: 16, width: 16);
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 48 : 16,
                    wide ? 40 : 20,
                    wide ? 48 : 16,
                    48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Greeting(name: name, wide: wide),
                      const SizedBox(height: 24),
                      const PlanSection(),
                      // Android only; renders nothing (and no gap) elsewhere.
                      const HealthCard(),
                      gap,
                      if (wide)
                        // Top-aligned, not IntrinsicHeight: the chart lays
                        // out with a LayoutBuilder, which cannot report an
                        // intrinsic height.
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: ProgressSection()),
                            gap,
                            Expanded(child: CoachSection()),
                          ],
                        )
                      else ...const [ProgressSection(), gap, CoachSection()],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

const double _wideBreakpoint = 840;
const double _maxContentWidth = 1040;
const double _maxProseWidth = 640;

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.wide});

  final String? name;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name == null ? 'Welcome to LionFit.' : 'Hi, $name.',
          style:
              (wide
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.15),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxProseWidth),
          child: Text(
            "Here is this week's plan, how your lifts are moving, and what "
            'to load next time.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
