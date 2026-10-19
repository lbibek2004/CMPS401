import 'package:flutter_test/flutter_test.dart';
import 'package:lionfit/features/home/domain/home_greeting.dart';

void main() {
  group('resolveGreetingName', () {
    test('prefers display_name when sign-up supplied one', () {
      expect(
        resolveGreetingName(
          metadata: {'display_name': 'Pao'},
          email: 'pao@selu.edu',
        ),
        'Pao',
      );
    });

    test('falls back to email when metadata has no display_name', () {
      expect(
        resolveGreetingName(metadata: {'other': 'x'}, email: 'pao@selu.edu'),
        'pao@selu.edu',
      );
    });

    test('falls back to email when display_name is blank or whitespace', () {
      expect(
        resolveGreetingName(metadata: {'display_name': '   '}, email: 'a@b.c'),
        'a@b.c',
      );
      expect(
        resolveGreetingName(metadata: {'display_name': ''}, email: 'a@b.c'),
        'a@b.c',
      );
    });

    test('falls back to email when display_name is not a string', () {
      expect(
        resolveGreetingName(metadata: {'display_name': 42}, email: 'a@b.c'),
        'a@b.c',
      );
    });

    test('trims surrounding whitespace off a usable display_name', () {
      expect(
        resolveGreetingName(metadata: {'display_name': '  Pao  '}, email: null),
        'Pao',
      );
    });

    test('returns null when there is nothing usable to show', () {
      expect(resolveGreetingName(metadata: null, email: null), isNull);
      expect(resolveGreetingName(metadata: {}, email: '  '), isNull);
    });
  });

  group('session helpers', () {
    test('tolerate a null session instead of throwing', () {
      expect(greetingNameFor(null), isNull);
      expect(accountEmailFor(null), isNull);
    });
  });
}
