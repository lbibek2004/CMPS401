import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Initializes the Supabase client once, at startup.
///
/// Returns true when the client is live. Returns false when configuration is
/// missing or initialization failed — the app still boots in that case and
/// shows a setup screen rather than crashing.
Future<bool> initSupabase() async {
  if (!Env.hasSupabase || Env.configurationProblem != null) return false;
  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        // Persists the session across reloads. On web this is localStorage,
        // which is what keeps a signed-in user signed in after F5.
        autoRefreshToken: true,
      ),
    );
    return true;
  } catch (error) {
    // Never let a backend misconfiguration take down the whole app.
    return false;
  }
}

/// The initialized client.
///
/// Throws if [initSupabase] has not succeeded. Callers that might run in the
/// unconfigured state should check [isSupabaseReady] first, or read the client
/// through `supabaseClientProvider`, which surfaces a clear error instead.
SupabaseClient get supabase => Supabase.instance.client;

bool get isSupabaseReady {
  try {
    Supabase.instance;
    return true;
  } catch (_) {
    return false;
  }
}
