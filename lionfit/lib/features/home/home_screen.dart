import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/router/app_router.dart';
import 'domain/home_greeting.dart';

/// The signed-in landing spot at `/home`.
///
/// Two things work today - logging sets and the 3D muscle map - and they are
/// the two cards at the top. Everything else is marked as not built yet
/// rather than faking a dashboard with invented numbers.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Null when the session has not restored yet, or when Supabase is not
    // configured at all. Both render fine; nothing below dereferences it.
    final session = ref.watch(sessionProvider);
    final name = greetingNameFor(session);
    final email = accountEmailFor(session);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LionFit'),
        actions: const [_SignOutButton(), SizedBox(width: 4)],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 48 : 20,
                    wide ? 40 : 24,
                    wide ? 48 : 20,
                    48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Greeting(name: name, wide: wide),
                      const SizedBox(height: 28),
                      _QuickActions(
                        availableWidth: _contentWidth(constraints, wide),
                      ),
                      SizedBox(height: wide ? 48 : 36),
                      _SectionLabel(
                        label: 'COMING NEXT',
                        caption:
                            'Not wired up yet. These fill in as the plan '
                            'generator and progress charts land.',
                      ),
                      const SizedBox(height: 20),
                      _ComingNextGrid(
                        availableWidth: _contentWidth(constraints, wide),
                      ),
                      if (email != null) ...[
                        const SizedBox(height: 40),
                        _AccountLine(email: email),
                      ],
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

/// Width left for content once the max-width clamp and the page padding are
/// taken out — the grid needs it to decide its column count.
double _contentWidth(BoxConstraints constraints, bool wide) {
  final clamped = constraints.maxWidth > _maxContentWidth
      ? _maxContentWidth
      : constraints.maxWidth;
  final horizontalPadding = (wide ? 48.0 : 20.0) * 2;
  final inner = clamped - horizontalPadding;
  return inner < 240 ? 240 : inner;
}

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
            'Log a session, then check which muscles you have actually been '
            'hitting.',
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

/// The two features that work today.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.availableWidth});

  final double availableWidth;

  @override
  Widget build(BuildContext context) {
    const spacing = 16.0;
    final columns = availableWidth >= 560 ? 2 : 1;
    final itemWidth = (availableWidth - spacing * (columns - 1)) / columns;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        SizedBox(
          width: itemWidth,
          child: _ActionCard(
            icon: Icons.fitness_center_outlined,
            title: 'Log a workout',
            body:
                'Pick exercises from the Rec Center catalog and log weight, '
                'reps and RPE for each set.',
            onTap: () => context.go(Routes.logWorkout),
          ),
        ),
        SizedBox(
          width: itemWidth,
          child: _ActionCard(
            icon: Icons.accessibility_new_outlined,
            title: 'Muscle map',
            body:
                'A 3D body colored by what you trained: red untrained, '
                'yellow less trained, green well trained.',
            onTap: () => context.go(Routes.muscleMap),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.caption});

  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxProseWidth),
          child: Text(
            caption,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ComingNextGrid extends StatelessWidget {
  const _ComingNextGrid({required this.availableWidth});

  final double availableWidth;

  static const _items = <(IconData, String, String)>[
    (
      Icons.calendar_today_outlined,
      "This week's plan",
      'The days you train, the lifts on each one, and the equipment they need.',
    ),
    (
      Icons.show_chart,
      'Progress',
      'A line per exercise: weight, reps and estimated 1RM as they move.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    const spacing = 16.0;
    final columns = availableWidth >= 560 ? 2 : 1;
    final itemWidth = (availableWidth - spacing * (columns - 1)) / columns;

    // Wrap rather than GridView: no fixed aspect ratio means a 200% text
    // scale grows the cards instead of clipping them.
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final (icon, title, body) in _items)
          SizedBox(
            width: itemWidth,
            child: _ComingNextCard(icon: icon, title: title, body: body),
          ),
      ],
    );
  }
}

class _ComingNextCard extends StatelessWidget {
  const _ComingNextCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Not tappable on purpose: a card that reacts but goes nowhere reads as
    // broken.
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            const _NotYetBadge(),
          ],
        ),
      ),
    );
  }
}

class _NotYetBadge extends StatelessWidget {
  const _NotYetBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Not available yet',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        const SizedBox(height: 16),
        Text(
          'Signed in as $email',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Stateful so the button can show the request in flight and surface a
/// failure. On success the router's auth listener redirects — this must not
/// navigate itself.
class _SignOutButton extends ConsumerStatefulWidget {
  const _SignOutButton();

  @override
  ConsumerState<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends ConsumerState<_SignOutButton> {
  bool _busy = false;

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider).signOut();
      // No navigation here on purpose: the redirect handles it.
    } catch (error) {
      if (!mounted) return;
      final message = error is AuthFailure
          ? error.message
          : 'Could not sign out. Please try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      // The widget is gone by now on a successful sign-out.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _busy ? null : _signOut,
      tooltip: 'Sign out',
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout),
    );
  }
}
