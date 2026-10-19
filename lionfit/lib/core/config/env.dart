/// Compile-time configuration.
///
/// Values arrive via `--dart-define-from-file=.env`:
///
/// ```bash
/// flutter run -d chrome --dart-define-from-file=.env
/// ```
///
/// `String.fromEnvironment` is a const constructor, so these are baked in at
/// build time. Nothing here is read from disk at runtime — a web build has no
/// filesystem to read from.
library;

class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  // Supabase renamed the client-side key: legacy projects issue a JWT "anon"
  // key, newer ones issue `sb_publishable_...`. Both go in the same slot and
  // both are safe to ship in a client build — they are constrained by RLS.
  // Prefer the new name, fall back to the old so existing .env files keep working.
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String _legacyAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static String get supabaseAnonKey =>
      _publishableKey.isNotEmpty ? _publishableKey : _legacyAnonKey;
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  /// Seed account identity. Development convenience only — never a credential.
  static const String seedUserEmail = String.fromEnvironment('SEED_USER_EMAIL');

  static bool get isDevelopment => appEnv != 'production';

  /// True when the app has enough configuration to reach Supabase.
  ///
  /// The app deliberately still boots when this is false: it renders a clear
  /// setup screen instead of crashing on a null client, so `flutter run` works
  /// before anyone has wired up a project.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Human-readable reason configuration is incomplete, or null when it is fine.
  static String? get configurationProblem {
    if (supabaseUrl.isEmpty && supabaseAnonKey.isEmpty) {
      return 'SUPABASE_URL and SUPABASE_ANON_KEY are both missing. '
          'Did you pass --dart-define-from-file=.env?';
    }
    if (supabaseUrl.isEmpty) return 'SUPABASE_URL is missing.';
    if (supabaseAnonKey.isEmpty) return 'SUPABASE_ANON_KEY is missing.';
    if (supabaseUrl.contains('YOUR_PROJECT_REF')) {
      return 'SUPABASE_URL is still the placeholder from .env.example.';
    }
    if (supabaseAnonKey.contains('YOUR_SUPABASE_ANON_KEY')) {
      return 'SUPABASE_ANON_KEY is still the placeholder from .env.example.';
    }
    // A pasted REST endpoint is the single most common setup mistake: the
    // client appends /rest/v1 and /auth/v1 itself, so the suffix breaks
    // every request with an error that points nowhere near the cause.
    if (supabaseUrl.contains('/rest/v1') || supabaseUrl.contains('/auth/v1')) {
      return 'SUPABASE_URL should be the bare project URL '
          '(https://<ref>.supabase.co) — strip the /rest/v1 or /auth/v1 suffix.';
    }
    return null;
  }
}
