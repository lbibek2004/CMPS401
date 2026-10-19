import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/core/widgets/setup_required_screen.dart';

void main() {
  testWidgets('SetupRequiredScreen names the problem and the fix', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SetupRequiredScreen(problem: 'SUPABASE_URL is missing.'),
      ),
    );

    expect(find.text('Configuration needed'), findsOneWidget);
    expect(find.text('SUPABASE_URL is missing.'), findsOneWidget);
    expect(find.textContaining('--dart-define-from-file=.env'), findsOneWidget);
  });
}
