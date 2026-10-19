import 'package:flutter/material.dart';

/// The LionFit type scale.
///
/// No font package is declared, so this rides the platform default (Roboto on
/// Android, the system UI stack on web). What is fixed here is the *scale*:
/// sizes, weights, line heights and tracking, so screens never set a font size
/// inline.
///
/// Sizes follow Material 3's roles. Headings are heavier than the M3 defaults
/// because this app is read one-handed between sets, and body sizes never drop
/// below 12 for anything a user has to read.
abstract final class AppTypography {
  /// The scale with colours applied from [scheme].
  ///
  /// Everything resolves to [ColorScheme.onSurface]; components that want
  /// lower emphasis (input labels, helper text, captions) override to
  /// [ColorScheme.onSurfaceVariant] in their own theme, which keeps the
  /// measured contrast decision in one place instead of spread across roles.
  static TextTheme textTheme(ColorScheme scheme) => _scale.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
    decorationColor: scheme.onSurface,
  );

  /// Returns [style] with tabular (fixed-width) figures.
  ///
  /// Use for any column of numbers that has to line up between rows - weight,
  /// reps, RPE, e1RM, rest-timer digits. Without it, proportional digits make
  /// a set table visibly ragged and a counting timer jitter.
  static TextStyle tabular(TextStyle style) => style.copyWith(
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  static const TextTheme _scale = TextTheme(
    displayLarge: TextStyle(
      fontSize: 57,
      height: 64 / 57,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    displayMedium: TextStyle(
      fontSize: 45,
      height: 52 / 45,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      height: 44 / 36,
      fontWeight: FontWeight.w700,
    ),
    headlineLarge: TextStyle(
      fontSize: 32,
      height: 40 / 32,
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 36 / 28,
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      height: 32 / 24,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.15,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );
}
