import 'package:supabase_flutter/supabase_flutter.dart';

/// How the signed-in user should be addressed on the dashboard.
///
/// Pure so it can be unit tested without a Supabase session: pass the raw
/// `user_metadata` map and the account email.
///
/// Order of preference:
/// 1. `display_name` from the sign-up metadata, when it is a non-blank string
/// 2. the account email
/// 3. null — nothing usable, the caller falls back to a generic greeting
String? resolveGreetingName({
  required Map<String, dynamic>? metadata,
  required String? email,
}) {
  final raw = metadata?['display_name'];
  if (raw is String) {
    final name = raw.trim();
    if (name.isNotEmpty) return name;
  }
  final trimmedEmail = email?.trim();
  if (trimmedEmail != null && trimmedEmail.isNotEmpty) return trimmedEmail;
  return null;
}

/// [resolveGreetingName] over a live session. Null-safe: a missing session
/// yields null rather than throwing.
String? greetingNameFor(Session? session) => resolveGreetingName(
  metadata: session?.user.userMetadata,
  email: session?.user.email,
);

/// The email to show in the account line, or null when there is none to show.
String? accountEmailFor(Session? session) {
  final email = session?.user.email?.trim();
  return (email == null || email.isEmpty) ? null : email;
}
