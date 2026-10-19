/// Pure, context-free validation for the LionFit auth forms.
///
/// Every rule here is also enforced by Supabase on the server. Running them on
/// the client first means the ordinary mistakes - empty field, typo'd email,
/// five-character password, mismatched confirmation - never cost a round trip
/// and never surface as a cryptic GoTrue message.
///
/// Plain static functions with no Flutter imports, so they are unit testable
/// without pumping a widget.
abstract final class AuthValidators {
  /// Supabase's own floor. Keep this in lockstep with the dashboard setting;
  /// if the project ever raises it, the server still rejects and
  /// `AuthFailure.message` explains why.
  static const minPasswordLength = 6;

  static const maxDisplayNameLength = 40;

  /// Deliberately permissive: one or more label characters, an `@`, a domain
  /// with at least one dot. Anything stricter starts rejecting addresses that
  /// are legal, and the server is the real authority anyway.
  static final RegExp _emailPattern = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );

  static String? email(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter your email address.';
    if (!_emailPattern.hasMatch(input)) {
      return 'That does not look like an email address.';
    }
    return null;
  }

  /// Not trimmed: leading and trailing spaces are legitimate password
  /// characters, and silently stripping them would lock people out.
  static String? password(String? value) {
    final input = value ?? '';
    if (input.isEmpty) return 'Enter your password.';
    if (input.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    final input = value ?? '';
    if (input.isEmpty) return 'Re-enter your password.';
    if (input != password) return 'Those passwords do not match.';
    return null;
  }

  static String? displayName(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter the name you want shown in the app.';
    if (input.length < 2) {
      return 'That is a little short - use at least 2 characters.';
    }
    if (input.length > maxDisplayNameLength) {
      return 'Keep it under $maxDisplayNameLength characters.';
    }
    return null;
  }
}
