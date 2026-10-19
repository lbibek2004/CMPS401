import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/config/env.dart';

/// Run with: flutter test --dart-define-from-file=.env
/// Skipped when no config is supplied, so plain `flutter test` stays green.
void main() {
  test('.env parses and SUPABASE_URL is a bare project URL', () {
    if (!Env.hasSupabase) {
      markTestSkipped('no --dart-define-from-file=.env supplied');
      return;
    }
    expect(Env.supabaseUrl, startsWith('https://'));
    expect(Env.supabaseUrl, isNot(contains('/rest/v1')));
    expect(Env.supabaseAnonKey.length, greaterThan(40));
    expect(Env.configurationProblem, isNull);
  });
}
