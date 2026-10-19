import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_bootstrap.dart';

/// The live Supabase client. Throws a readable error when unconfigured.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (!isSupabaseReady) {
    throw StateError(
      'Supabase is not initialized. Run with --dart-define-from-file=.env',
    );
  }
  return supabase;
});

/// Emits on every sign-in, sign-out, and token refresh.
final authChangesProvider = StreamProvider<AuthState>((ref) {
  if (!isSupabaseReady) return const Stream<AuthState>.empty();
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// The current session, or null when signed out.
///
/// Reads [authChangesProvider] so it recomputes on auth events, but falls back
/// to the client's restored session so a page refresh does not briefly report
/// "signed out" before the first stream event arrives.
final sessionProvider = Provider<Session?>((ref) {
  if (!isSupabaseReady) return null;
  final changes = ref.watch(authChangesProvider);
  final client = ref.watch(supabaseClientProvider);
  return changes.asData?.value.session ?? client.auth.currentSession;
});

final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider) != null,
);

/// Raised for auth failures that carry a message worth showing the user.
class AuthFailure implements Exception {
  AuthFailure(this.message, {this.isUnconfirmedEmail = false});

  final String message;
  final bool isUnconfirmedEmail;

  @override
  String toString() => message;
}

/// Sign-in / sign-up / sign-out. UI calls these; it never touches GoTrue directly.
class AuthController {
  AuthController(this._ref);

  final Ref _ref;

  GoTrueClient get _auth => _ref.read(supabaseClientProvider).auth;

  Future<void> signIn({required String email, required String password}) async {
    await _guard(
      () => _auth.signInWithPassword(email: email, password: password),
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    await _guard(
      () => _auth.signUp(
        email: email,
        password: password,
        data: displayName == null ? null : {'display_name': displayName},
      ),
    );
  }

  Future<void> signOut() => _guard(() => _auth.signOut());

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthException catch (error) {
      throw AuthFailure(
        _humanize(error),
        isUnconfirmedEmail: _isUnconfirmed(error),
      );
    } catch (error) {
      throw AuthFailure('Something went wrong. Please try again.');
    }
  }

  static bool _isUnconfirmed(AuthException error) {
    final code = error.code?.toLowerCase() ?? '';
    final message = error.message.toLowerCase();
    return code.contains('not_confirmed') || message.contains('not confirmed');
  }

  /// GoTrue messages are terse and sometimes cryptic. Translate the ones a
  /// student will actually hit; pass anything else through unchanged.
  static String _humanize(AuthException error) {
    final message = error.message.toLowerCase();
    if (_isUnconfirmed(error)) {
      return 'That email has not been confirmed yet. Check your inbox, or turn '
          'off "Confirm email" in the Supabase dashboard for development.';
    }
    if (message.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'An account with that email already exists. Try signing in.';
    }
    if (message.contains('password should be')) {
      return 'Password must be at least 6 characters.';
    }
    if (message.contains('unable to validate email')) {
      return 'That does not look like a valid email address.';
    }
    return error.message;
  }
}

final authControllerProvider = Provider<AuthController>(AuthController.new);
