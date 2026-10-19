/// Raw hex values for the LionFit design system.
///
/// Nothing outside `lib/core/theme/` should import this file. Screens read
/// colour through `Theme.of(context).colorScheme` or
/// `LionFitTokens.of(context)` - never a hex, never `Colors.green`.
///
/// Every value below was checked with the WCAG 2.1 relative-luminance formula.
/// The ratios in the doc comments are measured, not estimated. Where a value
/// carries text, the pairing is named explicitly.
library;

import 'package:flutter/material.dart';

/// The six fixed brand values. See `CLAUDE.md` - these do not change.
abstract final class BrandColors {
  // Dark theme.
  static const Color darkBase = Color(0xFF000000);
  static const Color darkPrimary = Color(0xFF1A5634);
  static const Color darkSecondary = Color(0xFFF8CB28);

  // Light theme.
  static const Color lightBase = Color(0xFFFFFFFF);
  static const Color lightPrimary = Color(0xFF0B4022);
  static const Color lightSecondary = Color(0xFFBF9C1F);
}

/// Derived values for the dark theme (base `#000000`).
///
/// A pure black base gives no free elevation, so the surface steps below are
/// explicit, slightly green-tinted near-blacks. They are deliberately *not*
/// high contrast against each other: a card is identified by its fill step
/// plus an [outlineVariant] edge, not by a strong boundary.
abstract final class DarkPalette {
  // --------------------------------------------------------------- surfaces
  /// Scaffold / page background. Contrast with [onSurface] is 18.00:1.
  static const Color surface = Color(0xFF000000);
  static const Color surfaceDim = Color(0xFF000000);
  static const Color surfaceBright = Color(0xFF2A332D);
  static const Color surfaceContainerLowest = Color(0xFF000000);
  static const Color surfaceContainerLow = Color(0xFF0A0F0C);

  /// Default card fill. 1.15:1 against [surface] - the step alone is subtle by
  /// design; cards also carry an [outlineVariant] edge.
  static const Color surfaceContainer = Color(0xFF101612);

  /// Text-field fill and raised sheets. 1.24:1 against [surface].
  static const Color surfaceContainerHigh = Color(0xFF171F1A);
  static const Color surfaceContainerHighest = Color(0xFF1F2823);

  // -------------------------------------------------------------------- ink
  /// Body text. 18.00:1 on [surface], 14.43:1 on [surfaceContainerHigh].
  static const Color onSurface = Color(0xFFE9EFEA);

  /// Secondary text, labels, hints. 11.97:1 on [surface], 9.59:1 on
  /// [surfaceContainerHigh], 8.63:1 on [surfaceContainerHighest].
  static const Color onSurfaceVariant = Color(0xFFBCC6BF);

  /// Boundary of interactive components (text fields, outlined controls).
  /// 6.79:1 on [surface], 5.44:1 on [surfaceContainerHigh] - clears the 3:1
  /// non-text requirement with room to spare.
  static const Color outline = Color(0xFF8B958E);

  /// Decorative dividers and card edges. 2.02:1 on [surface]; intentionally
  /// below 3:1 because it never carries required information.
  static const Color outlineVariant = Color(0xFF39423C);

  // ------------------------------------------------------------------ brand
  /// Brand fill (buttons, selected states). White on it measures 8.66:1.
  ///
  /// NOTE: 2.42:1 against [surface]. This is a *fill*, never a text colour on
  /// dark. Use [brandText] for brand-coloured text and icons.
  static const Color primary = BrandColors.darkPrimary;
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF14472B);
  static const Color onPrimaryContainer = Color(0xFFA6E0BC); // 7.13:1

  /// Brand green that survives as text/icon on a black base.
  /// 9.38:1 on [surface], 8.19:1 on [surfaceContainer], 6.77:1 on
  /// [surfaceContainerHighest].
  static const Color brandText = Color(0xFF4FC283);

  /// Brand hairline. 6.02:1 on [surface] - this is what makes a filled
  /// `#1A5634` button's boundary legible against pure black, and what the
  /// focus ring uses.
  static const Color brandBorder = Color(0xFF3E9A66);

  /// Accent / PR gold. 13.56:1 on [surface].
  static const Color secondary = BrandColors.darkSecondary;
  static const Color onSecondary = Color(0xFF231A00); // 11.13:1
  static const Color secondaryContainer = Color(0xFF4A3B00);
  static const Color onSecondaryContainer = Color(0xFFFBE08A); // 8.42:1

  /// Cool third hue - cardio, rest timers, informational chips.
  static const Color tertiary = Color(0xFF8FD0F0); // 12.45:1 on surface
  static const Color onTertiary = Color(0xFF00212F); // 9.89:1
  static const Color tertiaryContainer = Color(0xFF0E4659);
  static const Color onTertiaryContainer = Color(0xFFBFE6F8); // 7.79:1

  static const Color error = Color(0xFFFF8A80); // 9.20:1 on surface
  static const Color onError = Color(0xFF450A05); // 7.08:1
  static const Color errorContainer = Color(0xFF7A1710);
  static const Color onErrorContainer = Color(0xFFFFD9D4); // 8.24:1

  static const Color inverseSurface = Color(0xFFE9EFEA);
  static const Color onInverseSurface = Color(0xFF101612); // 15.71:1
  static const Color inversePrimary = Color(0xFF0B4022); // 10.17:1 on inverse

  // ----------------------------------------------------------------- status
  static const Color success = Color(0xFF4FC283); // 9.38:1 on surface
  static const Color onSuccess = Color(0xFF050806); // 8.98:1
  static const Color warning = Color(0xFFF2A94B); // 10.55:1 on surface
  static const Color onWarning = Color(0xFF050806); // 10.11:1
  static const Color danger = Color(0xFFFF8A80); // 9.20:1 on surface
  static const Color onDanger = Color(0xFF050806); // 8.81:1

  // -------------------------------------------------------------- set types
  static const Color setTypeWarmUp = Color(0xFF8FD0F0); // 12.45:1, L=0.572
  static const Color setTypeWorking = Color(0xFF4FC283); // 9.38:1,  L=0.419
  static const Color setTypeDropSet = Color(0xFFC15A15); // 4.74:1,  L=0.187
  static const Color setTypeSuperSet = Color(0xFFA98BE8); // 7.55:1, L=0.327
  static const Color onSetTypeWarmUp = Color(0xFF050806); // 11.93:1
  static const Color onSetTypeWorking = Color(0xFF050806); // 8.98:1
  static const Color onSetTypeDropSet = Color(0xFF050806); // 4.54:1
  static const Color onSetTypeSuperSet = Color(0xFF050806); // 7.23:1

  // ---------------------------------------------------------- intensity ramp
  /// Luminance climbs monotonically: 0.071, 0.163, 0.297, 0.454, 0.628. The
  /// ramp therefore still reads as an ordered scale under red-green colour
  /// blindness. Contrast against [surface]: 2.42, 4.26, 6.93, 10.07, 13.56.
  ///
  /// Step 0 is the brand primary and is the one value here below 3:1 against
  /// the base - unavoidable, because the brand fixes both `#1A5634` and
  /// `#000000`. It is acceptable as a large filled region on the 3D model,
  /// which paints it over the neutral body mesh rather than over the page. In
  /// a legend, where the swatch is small, give every swatch a
  /// `colorScheme.outline` border so the chip's boundary carries the 3:1
  /// instead of the fill.
  static const List<Color> intensityRamp = <Color>[
    BrandColors.darkPrimary, // #1A5634
    Color(0xFF2F7F4A),
    Color(0xFF55A646),
    Color(0xFFA8BE2E),
    BrandColors.darkSecondary, // #F8CB28
  ];

  /// "Not trained in this window". Deliberately neutral and *below* the ramp's
  /// luminance band (L=0.023 vs the ramp's 0.071-0.628), so it can never be
  /// mistaken for a low-intensity step even if hue is not perceived.
  static const Color intensityNone = Color(0xFF262B2E);

  // ----------------------------------------------------------- muscle status
  /// Red / yellow / green for the 3D muscle map. Fills on a lit model, not
  /// text. Luminance 0.20 / 0.62 / 0.30, so yellow stands out and red vs
  /// green still differ in lightness for red-green colour-blind viewers.
  static const Color muscleUntrained = Color(0xFFE5484D);
  static const Color muscleLessTrained = BrandColors.darkSecondary; // #F8CB28
  static const Color muscleWellTrained = Color(0xFF3DBE6E);

  // ----------------------------------------------------------- chart series
  /// Ordered so neighbouring series are never a red-green confusable pair.
  /// Contrast on [surface]: 9.38, 10.87, 13.56, 7.55, 4.74, 9.71.
  static const List<Color> chartSeries = <Color>[
    Color(0xFF4FC283), // green
    Color(0xFF7FC3E8), // blue
    Color(0xFFF8CB28), // gold
    Color(0xFFA98BE8), // violet
    Color(0xFFC15A15), // orange
    Color(0xFF3FC2C2), // teal
  ];

  // ------------------------------------------------------------ PR / records
  static const Color prAccent = BrandColors.darkSecondary;
  static const Color onPrAccent = Color(0xFF231A00); // 11.13:1
  static const Color prText = BrandColors.darkSecondary; // 13.56:1 on surface
  static const Color prSurface = Color(0xFF3A2E00); // prText on it: 8.64:1

  // --------------------------------------------------------------- contrast
  static const Color contrastInk = Color(0xFF050806);
  static const Color contrastPaper = Color(0xFFFFFFFF);
}

/// Derived values for the light theme (base `#FFFFFF`).
///
/// `#FFFFFF` with `#0B4022` is already a very high-contrast pair, so the
/// supporting surfaces are softened green-greys rather than more pure white.
abstract final class LightPalette {
  // --------------------------------------------------------------- surfaces
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDim = Color(0xFFDDE4DE);
  static const Color surfaceBright = Color(0xFFFFFFFF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF6F9F6);

  /// Default card fill. 1.11:1 against [surface], paired with an
  /// [outlineVariant] edge.
  static const Color surfaceContainer = Color(0xFFEFF4F0);

  /// Text-field fill. [onSurface] on it measures 15.56:1.
  static const Color surfaceContainerHigh = Color(0xFFE8EEE9);
  static const Color surfaceContainerHighest = Color(0xFFE0E7E1);

  // -------------------------------------------------------------------- ink
  /// Body text. 18.31:1 on [surface], 15.56:1 on [surfaceContainerHigh].
  static const Color onSurface = Color(0xFF111611);

  /// Secondary text, labels, hints. 9.16:1 on [surface], 7.78:1 on
  /// [surfaceContainerHigh].
  static const Color onSurfaceVariant = Color(0xFF424A43);

  /// Interactive component boundary. 4.69:1 on [surface], 3.99:1 on
  /// [surfaceContainerHigh].
  static const Color outline = Color(0xFF6D7670);

  /// Decorative dividers and card edges. 1.66:1 - never load-bearing.
  static const Color outlineVariant = Color(0xFFC2CBC5);

  // ------------------------------------------------------------------ brand
  /// Brand fill and brand text. White on it measures 11.86:1, and it measures
  /// 11.86:1 as text on [surface] - on light, one value serves both roles.
  static const Color primary = BrandColors.lightPrimary;
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFCBE7D5);
  static const Color onPrimaryContainer = Color(0xFF06301A); // 11.02:1

  /// 11.86:1 on [surface], 10.07:1 on [surfaceContainerHigh].
  static const Color brandText = BrandColors.lightPrimary;

  /// Outline-button border and focus ring. 6.35:1 on [surface], 5.39:1 on
  /// [surfaceContainerHigh]. Lighter than [primary] so a focused field does
  /// not read as a solid black box.
  static const Color brandBorder = Color(0xFF2E6B46);

  /// Accent / PR gold. This is a **fill only**: `#BF9C1F` as text on white is
  /// 2.63:1 and fails. Black on it is 7.99:1, so it carries dark text. For
  /// gold *text* on a light surface use [prText].
  static const Color secondary = BrandColors.lightSecondary;
  static const Color onSecondary = Color(0xFF231A00); // 6.55:1
  static const Color secondaryContainer = Color(0xFFF6E7B0);
  static const Color onSecondaryContainer = Color(0xFF3A2E00); // 10.81:1

  static const Color tertiary = Color(0xFF1D6A87); // 6.06:1 on surface
  static const Color onTertiary = Color(0xFFFFFFFF); // 6.06:1
  static const Color tertiaryContainer = Color(0xFFC7E7F5);
  static const Color onTertiaryContainer = Color(0xFF06303F); // 10.77:1

  static const Color error = Color(0xFFB3261E); // 6.54:1 on surface
  static const Color onError = Color(0xFFFFFFFF); // 6.54:1
  static const Color errorContainer = Color(0xFFF9DEDC);
  static const Color onErrorContainer = Color(0xFF410E0B); // 12.77:1

  static const Color inverseSurface = Color(0xFF1F2823);
  static const Color onInverseSurface = Color(0xFFEFF4F0);
  static const Color inversePrimary = Color(0xFF4FC283); // 6.77:1 on inverse

  // ----------------------------------------------------------------- status
  static const Color success = Color(0xFF146B37); // 6.59:1 on surface
  static const Color onSuccess = Color(0xFFFFFFFF); // 6.59:1
  static const Color warning = Color(0xFF8A5000); // 6.51:1 on surface
  static const Color onWarning = Color(0xFFFFFFFF); // 6.51:1
  static const Color danger = Color(0xFFB3261E); // 6.54:1 on surface
  static const Color onDanger = Color(0xFFFFFFFF); // 6.54:1

  // -------------------------------------------------------------- set types
  static const Color setTypeWarmUp = Color(0xFF1D6A87); // 6.06:1,  L=0.123
  static const Color setTypeWorking = BrandColors.lightPrimary; // 11.86, L=.039
  static const Color setTypeDropSet = Color(0xFFA3461A); // 6.09:1,  L=0.122
  static const Color setTypeSuperSet = Color(0xFF4A2F94); // 9.88:1, L=0.056
  static const Color onSetTypeWarmUp = Color(0xFFFFFFFF); // 6.06:1
  static const Color onSetTypeWorking = Color(0xFFFFFFFF); // 11.86:1
  static const Color onSetTypeDropSet = Color(0xFFFFFFFF); // 6.09:1
  static const Color onSetTypeSuperSet = Color(0xFFFFFFFF); // 9.88:1

  // ---------------------------------------------------------- intensity ramp
  /// Luminance climbs monotonically: 0.039, 0.067, 0.104, 0.160, 0.270.
  /// Contrast against [surface]: 11.86, 8.96, 6.82, 5.01, 3.28 - every step
  /// clears 3:1 on white, which is why the peak is `#AC8A11` and not the brand
  /// `#BF9C1F` (2.63:1). Same green-to-gold direction as the dark ramp.
  static const List<Color> intensityRamp = <Color>[
    BrandColors.lightPrimary, // #0B4022
    Color(0xFF18542C),
    Color(0xFF2E6722),
    Color(0xFF5B7915),
    Color(0xFFAC8A11),
  ];

  /// "Not trained in this window". Sits *above* the ramp's luminance band
  /// (L=0.686 vs 0.039-0.270) - the mirror of the dark theme's rule.
  static const Color intensityNone = Color(0xFFD3D9DC);

  // ----------------------------------------------------------- muscle status
  /// Same roles as the dark theme. Slightly deeper so the model does not wash
  /// out against the white page; legend swatches carry an outline border.
  static const Color muscleUntrained = Color(0xFFD32F2F);
  static const Color muscleLessTrained = Color(0xFFF2B705);
  static const Color muscleWellTrained = Color(0xFF2E9E5B);

  // ----------------------------------------------------------- chart series
  /// Contrast on [surface]: 8.32, 6.06, 5.56, 9.88, 6.09, 5.19 - all legible
  /// as 1-2px strokes and as legend text.
  static const List<Color> chartSeries = <Color>[
    Color(0xFF0F5A30), // green
    Color(0xFF1D6A87), // blue
    Color(0xFF806500), // gold
    Color(0xFF4A2F94), // violet
    Color(0xFFA3461A), // orange
    Color(0xFF0E7A72), // teal
  ];

  // ------------------------------------------------------------ PR / records
  static const Color prAccent = BrandColors.lightSecondary;
  static const Color onPrAccent = Color(0xFF231A00); // 6.55:1
  static const Color prText = Color(0xFF6E5700); // 6.94:1 on surface
  static const Color prSurface = Color(0xFFFBF0CE); // prText on it: 6.10:1

  // --------------------------------------------------------------- contrast
  static const Color contrastInk = Color(0xFF111611);
  static const Color contrastPaper = Color(0xFFFFFFFF);
}
