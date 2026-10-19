import 'package:flutter/material.dart';

import 'app_palette.dart';

/// The two [ColorScheme]s, written out by hand rather than seeded.
///
/// [ColorScheme.fromSeed] cannot produce these: the brand fixes `#1A5634` as
/// the dark primary and `#000000` as the dark base, a pairing tonal palettes
/// will not generate (M3 wants a light primary on a dark base). Every role is
/// therefore set explicitly, and the deprecated `background`, `onBackground`
/// and `surfaceVariant` roles are left alone.
abstract final class AppColorSchemes {
  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,

    primary: DarkPalette.primary,
    onPrimary: DarkPalette.onPrimary,
    primaryContainer: DarkPalette.primaryContainer,
    onPrimaryContainer: DarkPalette.onPrimaryContainer,
    primaryFixed: DarkPalette.primaryContainer,
    primaryFixedDim: DarkPalette.primary,
    onPrimaryFixed: DarkPalette.onPrimaryContainer,
    onPrimaryFixedVariant: DarkPalette.brandText,

    secondary: DarkPalette.secondary,
    onSecondary: DarkPalette.onSecondary,
    secondaryContainer: DarkPalette.secondaryContainer,
    onSecondaryContainer: DarkPalette.onSecondaryContainer,
    secondaryFixed: DarkPalette.secondaryContainer,
    secondaryFixedDim: DarkPalette.secondary,
    onSecondaryFixed: DarkPalette.onSecondaryContainer,
    onSecondaryFixedVariant: DarkPalette.onSecondaryContainer,

    tertiary: DarkPalette.tertiary,
    onTertiary: DarkPalette.onTertiary,
    tertiaryContainer: DarkPalette.tertiaryContainer,
    onTertiaryContainer: DarkPalette.onTertiaryContainer,
    tertiaryFixed: DarkPalette.tertiaryContainer,
    tertiaryFixedDim: DarkPalette.tertiary,
    onTertiaryFixed: DarkPalette.onTertiaryContainer,
    onTertiaryFixedVariant: DarkPalette.onTertiaryContainer,

    error: DarkPalette.error,
    onError: DarkPalette.onError,
    errorContainer: DarkPalette.errorContainer,
    onErrorContainer: DarkPalette.onErrorContainer,

    surface: DarkPalette.surface,
    onSurface: DarkPalette.onSurface,
    surfaceDim: DarkPalette.surfaceDim,
    surfaceBright: DarkPalette.surfaceBright,
    surfaceContainerLowest: DarkPalette.surfaceContainerLowest,
    surfaceContainerLow: DarkPalette.surfaceContainerLow,
    surfaceContainer: DarkPalette.surfaceContainer,
    surfaceContainerHigh: DarkPalette.surfaceContainerHigh,
    surfaceContainerHighest: DarkPalette.surfaceContainerHighest,
    onSurfaceVariant: DarkPalette.onSurfaceVariant,

    outline: DarkPalette.outline,
    outlineVariant: DarkPalette.outlineVariant,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),

    inverseSurface: DarkPalette.inverseSurface,
    onInverseSurface: DarkPalette.onInverseSurface,
    inversePrimary: DarkPalette.inversePrimary,

    // The tonal elevation overlay is disabled app-wide (see AppTheme), so this
    // only matters for widgets that read it directly.
    surfaceTint: DarkPalette.primary,
  );

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,

    primary: LightPalette.primary,
    onPrimary: LightPalette.onPrimary,
    primaryContainer: LightPalette.primaryContainer,
    onPrimaryContainer: LightPalette.onPrimaryContainer,
    primaryFixed: LightPalette.primaryContainer,
    primaryFixedDim: LightPalette.inversePrimary,
    onPrimaryFixed: LightPalette.onPrimaryContainer,
    onPrimaryFixedVariant: LightPalette.brandBorder,

    secondary: LightPalette.secondary,
    onSecondary: LightPalette.onSecondary,
    secondaryContainer: LightPalette.secondaryContainer,
    onSecondaryContainer: LightPalette.onSecondaryContainer,
    secondaryFixed: LightPalette.secondaryContainer,
    secondaryFixedDim: LightPalette.secondary,
    onSecondaryFixed: LightPalette.onSecondaryContainer,
    onSecondaryFixedVariant: LightPalette.onSecondaryContainer,

    tertiary: LightPalette.tertiary,
    onTertiary: LightPalette.onTertiary,
    tertiaryContainer: LightPalette.tertiaryContainer,
    onTertiaryContainer: LightPalette.onTertiaryContainer,
    tertiaryFixed: LightPalette.tertiaryContainer,
    tertiaryFixedDim: LightPalette.tertiary,
    onTertiaryFixed: LightPalette.onTertiaryContainer,
    onTertiaryFixedVariant: LightPalette.onTertiaryContainer,

    error: LightPalette.error,
    onError: LightPalette.onError,
    errorContainer: LightPalette.errorContainer,
    onErrorContainer: LightPalette.onErrorContainer,

    surface: LightPalette.surface,
    onSurface: LightPalette.onSurface,
    surfaceDim: LightPalette.surfaceDim,
    surfaceBright: LightPalette.surfaceBright,
    surfaceContainerLowest: LightPalette.surfaceContainerLowest,
    surfaceContainerLow: LightPalette.surfaceContainerLow,
    surfaceContainer: LightPalette.surfaceContainer,
    surfaceContainerHigh: LightPalette.surfaceContainerHigh,
    surfaceContainerHighest: LightPalette.surfaceContainerHighest,
    onSurfaceVariant: LightPalette.onSurfaceVariant,

    outline: LightPalette.outline,
    outlineVariant: LightPalette.outlineVariant,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),

    inverseSurface: LightPalette.inverseSurface,
    onInverseSurface: LightPalette.onInverseSurface,
    inversePrimary: LightPalette.inversePrimary,

    surfaceTint: LightPalette.primary,
  );
}
