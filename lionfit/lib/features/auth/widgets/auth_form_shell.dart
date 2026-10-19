import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lionfit/core/router/app_router.dart';

/// Shared chrome for the sign-in and sign-up screens.
///
/// LionFit runs in a browser at desktop widths, so the form is capped at
/// [_maxFormWidth] and centred - a text field stretched across 1920px reads as
/// broken. At tablet width and up the form gets card chrome; below that it
/// sits flat on the background, which is what a phone expects.
///
/// Everything lives in one [SingleChildScrollView] so the Android on-screen
/// keyboard can never trap a field off screen.
class AuthFormShell extends StatelessWidget {
  const AuthFormShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    required this.footerPrompt,
    required this.footerAction,
    required this.footerRoute,
  });

  final String title;
  final String subtitle;
  final Widget form;

  /// "Already have an account?" / "New to LionFit?"
  final String footerPrompt;

  /// The link label next to [footerPrompt].
  final String footerAction;

  /// Where that link goes. This is the one navigation the screens perform
  /// themselves - sign-in success is the router's job, not ours.
  final String footerRoute;

  static const double _maxFormWidth = 420;
  static const double _cardBreakpoint = 520;
  static const double _verticalPadding = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final roomy = constraints.maxWidth >= _cardBreakpoint;

            // Fill the viewport so the form sits vertically centred on a tall
            // desktop window, while still scrolling once content outgrows it.
            final minHeight = constraints.maxHeight.isFinite
                ? math.max(0.0, constraints.maxHeight - _verticalPadding * 2)
                : 0.0;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: roomy ? 32 : 20,
                vertical: _verticalPadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxFormWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BrandMark(),
                        const SizedBox(height: 24),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (roomy)
                          Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: form,
                            ),
                          )
                        else
                          form,
                        const SizedBox(height: 16),
                        _Footer(
                          prompt: footerPrompt,
                          action: footerAction,
                          route: footerRoute,
                        ),
                        TextButton(
                          onPressed: () => context.go(Routes.landing),
                          child: const Text('Back to the LionFit home page'),
                        ),
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

/// Primary-on-onPrimary by construction, so the mark stays legible whatever
/// the design system does to the palette.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Wrap, not Row: at large text scales `headlineSmall` outgrows the space
    // left beside the fixed-size badge on a narrow viewport, and a Row has
    // nowhere to put the excess. Wrap drops the wordmark below the badge
    // instead of overflowing. Covered by test/smoke/screens_render_test.dart.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.fitness_center, size: 26, color: scheme.onPrimary),
        ),
        Text(
          'LionFit',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.prompt,
    required this.action,
    required this.route,
  });

  final String prompt;
  final String action;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Wrap, not Row: at 320px the prompt and the link need two lines.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          prompt,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        TextButton(onPressed: () => context.go(route), child: Text(action)),
      ],
    );
  }
}
