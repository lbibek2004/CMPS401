import 'package:flutter/material.dart';

/// How loudly a notice should read. Both tones draw their colours from
/// [ColorScheme] container roles, so they stay legible in either theme.
enum AuthNoticeTone {
  /// Something failed and the user cannot continue.
  error,

  /// Nothing broke, but the user is stuck until someone changes a setting.
  caution,
}

/// An inline message block that sits inside the form, above the submit button.
///
/// Deliberately not a SnackBar: a SnackBar auto-dismisses, and the most
/// important message this app shows (see [AuthNotice.unconfirmedEmail]) is
/// several sentences of instructions that nobody can read in four seconds.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    super.key,
    required this.title,
    required this.message,
    this.tone = AuthNoticeTone.error,
    this.steps = const <String>[],
    this.stepsTitle,
    this.footnote,
  });

  /// The failure this team will hit first and most often.
  ///
  /// LionFit signs up with placeholder addresses that no mailbox ever
  /// receives, so if "Confirm email" is still on in the Supabase dashboard the
  /// confirmation link can never be clicked and the account can never sign in.
  /// There is no way for the app to fix that from here - the only resolution
  /// is a dashboard toggle - so the notice spells out exactly which toggle.
  const AuthNotice.unconfirmedEmail({
    super.key,
    required this.title,
    required this.message,
    this.tone = AuthNoticeTone.error,
  }) : steps = const <String>[
         'Open your Supabase project, then Authentication > Sign In / Providers > Email.',
         'Switch "Confirm email" OFF and save.',
         'Come back and try again - the existing account still works, no need to sign up twice.',
       ],
       stepsTitle = 'Fix this in the Supabase dashboard (development only)',
       footnote =
           'LionFit development accounts use placeholder addresses that never '
           'receive mail, so the confirmation link can never be clicked. Email '
           'confirmation has to stay off until the project uses real inboxes.';

  final String title;
  final String message;
  final AuthNoticeTone tone;
  final List<String> steps;
  final String? stepsTitle;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (Color background, Color foreground, IconData icon) = switch (tone) {
      AuthNoticeTone.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      AuthNoticeTone.caution => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.mark_email_unread_outlined,
      ),
    };

    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(color: foreground);
    final stepStyle = theme.textTheme.bodySmall?.copyWith(
      color: foreground,
      height: 1.35,
    );

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: foreground.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: bodyStyle),
                  if (steps.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (stepsTitle != null) ...[
                            Text(
                              stepsTitle!,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          for (var i = 0; i < steps.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    child: Text('${i + 1}.', style: stepStyle),
                                  ),
                                  Expanded(
                                    child: Text(steps[i], style: stepStyle),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (footnote != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      footnote!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
