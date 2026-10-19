import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Design tokens Material's [ColorScheme] has no slot for, plus the spacing and
/// radius scales.
///
/// Registered on both [ThemeData] objects, so it is always reachable:
///
/// ```dart
/// final tokens = LionFitTokens.of(context);
/// Container(color: tokens.setTypeDropSet);
/// ```
///
/// Both themes always define every token. If a token is added to one it is
/// added to the other in the same change.
@immutable
class LionFitTokens extends ThemeExtension<LionFitTokens> {
  const LionFitTokens({
    required this.brandText,
    required this.brandBorder,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.setTypeWarmUp,
    required this.onSetTypeWarmUp,
    required this.setTypeWorking,
    required this.onSetTypeWorking,
    required this.setTypeDropSet,
    required this.onSetTypeDropSet,
    required this.setTypeSuperSet,
    required this.onSetTypeSuperSet,
    required this.intensityRamp,
    required this.intensityNone,
    required this.muscleUntrained,
    required this.muscleLessTrained,
    required this.muscleWellTrained,
    required this.chartSeries,
    required this.prAccent,
    required this.onPrAccent,
    required this.prText,
    required this.prSurface,
    required this.contrastInk,
    required this.contrastPaper,
    required this.spaceXs,
    required this.spaceSm,
    required this.spaceMd,
    required this.spaceLg,
    required this.spaceXl,
    required this.space2xl,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXl,
    required this.radiusPill,
  });

  // ---------------------------------------------------------------- brand ---

  /// Brand green that is legible **as text or an icon** on the theme's
  /// surfaces.
  ///
  /// This is not the same thing as [ColorScheme.primary]. On dark, the brand
  /// primary `#1A5634` is only 2.42:1 against `#000000`; it works as a button
  /// fill (white on it is 8.66:1) but not as a label. Reach for [brandText]
  /// whenever brand colour is carrying glyphs rather than filling a shape.
  ///
  /// Dark `#4FC283` (9.38:1 on base) / light `#0B4022` (11.86:1 on base).
  final Color brandText;

  /// Brand stroke for focus rings, outlined-control borders, and the hairline
  /// that keeps a filled brand button's edge visible on a pure-black base.
  ///
  /// Dark `#3E9A66` (6.02:1 on base) / light `#2E6B46` (6.35:1 on base).
  /// Both clear the 3:1 non-text requirement.
  final Color brandBorder;

  // --------------------------------------------------------------- status ---

  /// Session completed, synced, goal met. Doubles as a text colour on surface
  /// (dark 9.38:1, light 6.59:1) and as a badge fill with [onSuccess].
  final Color success;
  final Color onSuccess;

  /// Deload advised, equipment unavailable, stale plan. Dark 10.55:1 on base,
  /// light 6.51:1.
  final Color warning;
  final Color onWarning;

  /// Destructive and failure states. Mirrors [ColorScheme.error] so a screen
  /// may use either name; dark 9.20:1 on base, light 6.54:1.
  final Color danger;
  final Color onDanger;

  // ------------------------------------------------------------ set types ---

  /// Warm-up set. Cool blue. Dark `#8FD0F0` / light `#1D6A87`.
  ///
  /// {@template lionfit.setType.affordance}
  /// **Colour is never the only signal.** A set-type marker in a dense log row
  /// must pair its colour with the non-colour affordance below, because the
  /// green/orange pair (working vs drop set) and the blue/violet pair (warm-up
  /// vs superset) are the two combinations red-green colour blindness
  /// compresses. Luminance was separated within each of those pairs on purpose
  /// - dark L 0.419 vs 0.187 and 0.572 vs 0.327; light L 0.039 vs 0.122 and
  /// 0.123 vs 0.056 - but luminance alone is not an identifier.
  ///
  /// Intended affordances, in order of how a row should be read:
  ///
  /// | Set type  | Glyph | Shape                                        |
  /// | --------- | ----- | -------------------------------------------- |
  /// | warm-up   | `WU`  | outlined chip, no fill - lowest weight       |
  /// | working   | none  | solid chip - the default, needs no decoration |
  /// | drop set  | `DS` with a down-chevron | solid chip plus a stepped left edge |
  /// | superset  | `SS` with a link/swap glyph | solid chip plus a bracket spanning the joined rows |
  ///
  /// A row stripped of all colour must still be readable from the glyph and
  /// the shape alone. Verify that by rendering the log in greyscale.
  /// {@endtemplate}
  final Color setTypeWarmUp;
  final Color onSetTypeWarmUp;

  /// Working set - the default. Brand green.
  ///
  /// {@macro lionfit.setType.affordance}
  final Color setTypeWorking;
  final Color onSetTypeWorking;

  /// Drop set. Deep orange.
  ///
  /// {@macro lionfit.setType.affordance}
  final Color setTypeDropSet;
  final Color onSetTypeDropSet;

  /// Superset. Violet.
  ///
  /// {@macro lionfit.setType.affordance}
  final Color setTypeSuperSet;
  final Color onSetTypeSuperSet;

  // ------------------------------------------------------------- intensity ---

  /// Muscle-group intensity, primary -> secondary, five steps.
  ///
  /// Feeds the 3D muscle map's 16 `baseColorFactor` writes and the legend
  /// beside it. Index 0 is the lowest tracked intensity, index 4 the peak.
  ///
  /// Intensity is **not encoded in hue alone**: relative luminance rises
  /// monotonically across the ramp in both themes (dark 0.071 -> 0.628, light
  /// 0.039 -> 0.270) while saturation climbs with it, so the ordering survives
  /// red-green colour blindness and greyscale printing.
  ///
  /// Prefer [intensityAt] over indexing when the source value is continuous.
  final List<Color> intensityRamp;

  /// A muscle group with no logged volume in the selected window.
  ///
  /// Distinct from every ramp step, not merely a dimmer version of step 0: it
  /// is neutral, and it sits outside the ramp's luminance band (below it on
  /// dark, above it on light). Pair it with an explicit "no data" legend entry
  /// rather than leaving the viewer to infer it.
  final Color intensityNone;

  // ------------------------------------------------------- muscle status ---

  /// The muscle map's three-state traffic light: red = not trained in the
  /// window, yellow = trained but under target, green = at or over target.
  /// See `lib/core/training/muscle_status.dart` for the thresholds.
  ///
  /// These are *fills* for the 3D model and legend swatches. Red and green are
  /// a colour-blind confusable pair, so the luminance is spread (yellow is the
  /// brightest of the three) and every place these appear also carries a text
  /// label - hue is never the only signal.
  final Color muscleUntrained;
  final Color muscleLessTrained;
  final Color muscleWellTrained;

  // ----------------------------------------------------------- chart series ---

  /// Line/bar series colours for progress graphs, in assignment order.
  ///
  /// Neighbouring entries are never a red-green confusable pair, and every
  /// entry clears 4.5:1 against its base so the same colour can label the
  /// legend. For more than three concurrent series, also vary dash pattern or
  /// marker shape - six hues is past the point where hue alone is reliable.
  final List<Color> chartSeries;

  // -------------------------------------------------------------- PR / records ---

  /// Personal-record badge fill. This is what secondary is for.
  /// Dark `#F8CB28`, light `#BF9C1F`; pair with [onPrAccent].
  final Color prAccent;
  final Color onPrAccent;

  /// Gold **text** on a normal surface.
  ///
  /// On light this is not [prAccent]: `#BF9C1F` on `#FFFFFF` is 2.63:1 and
  /// fails body text outright. [prText] is `#6E5700` (6.94:1). On dark the
  /// brand gold is already 13.56:1, so the two are the same value there.
  final Color prText;

  /// Subtle gold-tinted background for a PR banner or celebration row.
  /// [prText] on it measures 8.64:1 (dark) / 6.10:1 (light).
  final Color prSurface;

  // ------------------------------------------------------------- contrast ---

  /// Near-black of this theme, for text on a light fill. See [onColor].
  final Color contrastInk;

  /// Near-white of this theme, for text on a dark fill. See [onColor].
  final Color contrastPaper;

  // -------------------------------------------------------------- spacing ---

  /// 4 - icon-to-label, chip internals.
  final double spaceXs;

  /// 8 - between tightly related elements.
  final double spaceSm;

  /// 12 - inside a dense log row.
  final double spaceMd;

  /// 16 - default padding, card insets, screen gutters on phones.
  final double spaceLg;

  /// 24 - between sections.
  final double spaceXl;

  /// 32 - above a page title, below the last card.
  final double space2xl;

  // --------------------------------------------------------------- radius ---

  /// 8 - chips, small badges, set-type markers.
  final double radiusSm;

  /// 12 - buttons and text fields.
  final double radiusMd;

  /// 16 - cards, sheets, dialogs.
  final double radiusLg;

  /// 28 - bottom sheets, hero surfaces.
  final double radiusXl;

  /// Fully rounded. Use for pills and avatars.
  final double radiusPill;

  // ------------------------------------------------------------- behaviour ---

  /// The intensity colour for a normalised value in `[0, 1]`.
  ///
  /// Interpolates between ramp steps, so a continuous volume score maps to a
  /// continuous colour. Values outside the range are clamped. Use
  /// [intensityNone] for "no data" - do not pass 0 for it.
  Color intensityAt(double t) {
    if (intensityRamp.isEmpty) return intensityNone;
    if (intensityRamp.length == 1) return intensityRamp.first;
    final double clamped = t.clamp(0.0, 1.0);
    final double scaled = clamped * (intensityRamp.length - 1);
    final int index = scaled.floor().clamp(0, intensityRamp.length - 2);
    return Color.lerp(
      intensityRamp[index],
      intensityRamp[index + 1],
      scaled - index,
    )!;
  }

  /// The intensity colour for a discrete step, clamped to the ramp's bounds.
  Color intensityStep(int step) =>
      intensityRamp[step.clamp(0, intensityRamp.length - 1)];

  /// A chart series colour, wrapping if more series than the palette holds.
  Color chartSeriesAt(int index) =>
      chartSeries[index.abs() % chartSeries.length];

  /// Picks [contrastInk] or [contrastPaper] - whichever measures higher
  /// contrast against [background].
  ///
  /// For the generated fills ([intensityRamp], [chartSeries]) where a static
  /// `on` token would be guesswork. The fixed pairs - status, set types, PR -
  /// already ship an explicit `on` colour; prefer those.
  Color onColor(Color background) =>
      _ratio(contrastInk, background) >= _ratio(contrastPaper, background)
      ? contrastInk
      : contrastPaper;

  static double _ratio(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Tokens for the current theme.
  ///
  /// Falls back to [LionFitTokens.light] if the extension was not registered,
  /// so a widget rendered outside a [MaterialApp] still draws something sane
  /// instead of throwing.
  static LionFitTokens of(BuildContext context) =>
      Theme.of(context).extension<LionFitTokens>() ?? light;

  // ------------------------------------------------------------ instances ---

  static const LionFitTokens dark = LionFitTokens(
    brandText: DarkPalette.brandText,
    brandBorder: DarkPalette.brandBorder,
    success: DarkPalette.success,
    onSuccess: DarkPalette.onSuccess,
    warning: DarkPalette.warning,
    onWarning: DarkPalette.onWarning,
    danger: DarkPalette.danger,
    onDanger: DarkPalette.onDanger,
    setTypeWarmUp: DarkPalette.setTypeWarmUp,
    onSetTypeWarmUp: DarkPalette.onSetTypeWarmUp,
    setTypeWorking: DarkPalette.setTypeWorking,
    onSetTypeWorking: DarkPalette.onSetTypeWorking,
    setTypeDropSet: DarkPalette.setTypeDropSet,
    onSetTypeDropSet: DarkPalette.onSetTypeDropSet,
    setTypeSuperSet: DarkPalette.setTypeSuperSet,
    onSetTypeSuperSet: DarkPalette.onSetTypeSuperSet,
    intensityRamp: DarkPalette.intensityRamp,
    intensityNone: DarkPalette.intensityNone,
    muscleUntrained: DarkPalette.muscleUntrained,
    muscleLessTrained: DarkPalette.muscleLessTrained,
    muscleWellTrained: DarkPalette.muscleWellTrained,
    chartSeries: DarkPalette.chartSeries,
    prAccent: DarkPalette.prAccent,
    onPrAccent: DarkPalette.onPrAccent,
    prText: DarkPalette.prText,
    prSurface: DarkPalette.prSurface,
    contrastInk: DarkPalette.contrastInk,
    contrastPaper: DarkPalette.contrastPaper,
    spaceXs: _spaceXs,
    spaceSm: _spaceSm,
    spaceMd: _spaceMd,
    spaceLg: _spaceLg,
    spaceXl: _spaceXl,
    space2xl: _space2xl,
    radiusSm: _radiusSm,
    radiusMd: _radiusMd,
    radiusLg: _radiusLg,
    radiusXl: _radiusXl,
    radiusPill: _radiusPill,
  );

  static const LionFitTokens light = LionFitTokens(
    brandText: LightPalette.brandText,
    brandBorder: LightPalette.brandBorder,
    success: LightPalette.success,
    onSuccess: LightPalette.onSuccess,
    warning: LightPalette.warning,
    onWarning: LightPalette.onWarning,
    danger: LightPalette.danger,
    onDanger: LightPalette.onDanger,
    setTypeWarmUp: LightPalette.setTypeWarmUp,
    onSetTypeWarmUp: LightPalette.onSetTypeWarmUp,
    setTypeWorking: LightPalette.setTypeWorking,
    onSetTypeWorking: LightPalette.onSetTypeWorking,
    setTypeDropSet: LightPalette.setTypeDropSet,
    onSetTypeDropSet: LightPalette.onSetTypeDropSet,
    setTypeSuperSet: LightPalette.setTypeSuperSet,
    onSetTypeSuperSet: LightPalette.onSetTypeSuperSet,
    intensityRamp: LightPalette.intensityRamp,
    intensityNone: LightPalette.intensityNone,
    muscleUntrained: LightPalette.muscleUntrained,
    muscleLessTrained: LightPalette.muscleLessTrained,
    muscleWellTrained: LightPalette.muscleWellTrained,
    chartSeries: LightPalette.chartSeries,
    prAccent: LightPalette.prAccent,
    onPrAccent: LightPalette.onPrAccent,
    prText: LightPalette.prText,
    prSurface: LightPalette.prSurface,
    contrastInk: LightPalette.contrastInk,
    contrastPaper: LightPalette.contrastPaper,
    spaceXs: _spaceXs,
    spaceSm: _spaceSm,
    spaceMd: _spaceMd,
    spaceLg: _spaceLg,
    spaceXl: _spaceXl,
    space2xl: _space2xl,
    radiusSm: _radiusSm,
    radiusMd: _radiusMd,
    radiusLg: _radiusLg,
    radiusXl: _radiusXl,
    radiusPill: _radiusPill,
  );

  // The geometry scales do not change with brightness, but they live on the
  // extension so screens have one place to read every token from.
  static const double _spaceXs = 4;
  static const double _spaceSm = 8;
  static const double _spaceMd = 12;
  static const double _spaceLg = 16;
  static const double _spaceXl = 24;
  static const double _space2xl = 32;
  static const double _radiusSm = 8;
  static const double _radiusMd = 12;
  static const double _radiusLg = 16;
  static const double _radiusXl = 28;
  static const double _radiusPill = 999;

  // ------------------------------------------------------- ThemeExtension ---

  @override
  LionFitTokens copyWith({
    Color? brandText,
    Color? brandBorder,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? setTypeWarmUp,
    Color? onSetTypeWarmUp,
    Color? setTypeWorking,
    Color? onSetTypeWorking,
    Color? setTypeDropSet,
    Color? onSetTypeDropSet,
    Color? setTypeSuperSet,
    Color? onSetTypeSuperSet,
    List<Color>? intensityRamp,
    Color? intensityNone,
    Color? muscleUntrained,
    Color? muscleLessTrained,
    Color? muscleWellTrained,
    List<Color>? chartSeries,
    Color? prAccent,
    Color? onPrAccent,
    Color? prText,
    Color? prSurface,
    Color? contrastInk,
    Color? contrastPaper,
    double? spaceXs,
    double? spaceSm,
    double? spaceMd,
    double? spaceLg,
    double? spaceXl,
    double? space2xl,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXl,
    double? radiusPill,
  }) {
    return LionFitTokens(
      brandText: brandText ?? this.brandText,
      brandBorder: brandBorder ?? this.brandBorder,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      setTypeWarmUp: setTypeWarmUp ?? this.setTypeWarmUp,
      onSetTypeWarmUp: onSetTypeWarmUp ?? this.onSetTypeWarmUp,
      setTypeWorking: setTypeWorking ?? this.setTypeWorking,
      onSetTypeWorking: onSetTypeWorking ?? this.onSetTypeWorking,
      setTypeDropSet: setTypeDropSet ?? this.setTypeDropSet,
      onSetTypeDropSet: onSetTypeDropSet ?? this.onSetTypeDropSet,
      setTypeSuperSet: setTypeSuperSet ?? this.setTypeSuperSet,
      onSetTypeSuperSet: onSetTypeSuperSet ?? this.onSetTypeSuperSet,
      intensityRamp: intensityRamp ?? this.intensityRamp,
      intensityNone: intensityNone ?? this.intensityNone,
      muscleUntrained: muscleUntrained ?? this.muscleUntrained,
      muscleLessTrained: muscleLessTrained ?? this.muscleLessTrained,
      muscleWellTrained: muscleWellTrained ?? this.muscleWellTrained,
      chartSeries: chartSeries ?? this.chartSeries,
      prAccent: prAccent ?? this.prAccent,
      onPrAccent: onPrAccent ?? this.onPrAccent,
      prText: prText ?? this.prText,
      prSurface: prSurface ?? this.prSurface,
      contrastInk: contrastInk ?? this.contrastInk,
      contrastPaper: contrastPaper ?? this.contrastPaper,
      spaceXs: spaceXs ?? this.spaceXs,
      spaceSm: spaceSm ?? this.spaceSm,
      spaceMd: spaceMd ?? this.spaceMd,
      spaceLg: spaceLg ?? this.spaceLg,
      spaceXl: spaceXl ?? this.spaceXl,
      space2xl: space2xl ?? this.space2xl,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
      radiusPill: radiusPill ?? this.radiusPill,
    );
  }

  @override
  LionFitTokens lerp(covariant ThemeExtension<LionFitTokens>? other, double t) {
    if (other is! LionFitTokens) return this;
    return LionFitTokens(
      brandText: Color.lerp(brandText, other.brandText, t)!,
      brandBorder: Color.lerp(brandBorder, other.brandBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      setTypeWarmUp: Color.lerp(setTypeWarmUp, other.setTypeWarmUp, t)!,
      onSetTypeWarmUp: Color.lerp(onSetTypeWarmUp, other.onSetTypeWarmUp, t)!,
      setTypeWorking: Color.lerp(setTypeWorking, other.setTypeWorking, t)!,
      onSetTypeWorking: Color.lerp(
        onSetTypeWorking,
        other.onSetTypeWorking,
        t,
      )!,
      setTypeDropSet: Color.lerp(setTypeDropSet, other.setTypeDropSet, t)!,
      onSetTypeDropSet: Color.lerp(
        onSetTypeDropSet,
        other.onSetTypeDropSet,
        t,
      )!,
      setTypeSuperSet: Color.lerp(setTypeSuperSet, other.setTypeSuperSet, t)!,
      onSetTypeSuperSet: Color.lerp(
        onSetTypeSuperSet,
        other.onSetTypeSuperSet,
        t,
      )!,
      intensityRamp: _lerpColors(intensityRamp, other.intensityRamp, t),
      intensityNone: Color.lerp(intensityNone, other.intensityNone, t)!,
      muscleUntrained: Color.lerp(muscleUntrained, other.muscleUntrained, t)!,
      muscleLessTrained: Color.lerp(
        muscleLessTrained,
        other.muscleLessTrained,
        t,
      )!,
      muscleWellTrained: Color.lerp(
        muscleWellTrained,
        other.muscleWellTrained,
        t,
      )!,
      chartSeries: _lerpColors(chartSeries, other.chartSeries, t),
      prAccent: Color.lerp(prAccent, other.prAccent, t)!,
      onPrAccent: Color.lerp(onPrAccent, other.onPrAccent, t)!,
      prText: Color.lerp(prText, other.prText, t)!,
      prSurface: Color.lerp(prSurface, other.prSurface, t)!,
      contrastInk: Color.lerp(contrastInk, other.contrastInk, t)!,
      contrastPaper: Color.lerp(contrastPaper, other.contrastPaper, t)!,
      spaceXs: lerpDouble(spaceXs, other.spaceXs, t)!,
      spaceSm: lerpDouble(spaceSm, other.spaceSm, t)!,
      spaceMd: lerpDouble(spaceMd, other.spaceMd, t)!,
      spaceLg: lerpDouble(spaceLg, other.spaceLg, t)!,
      spaceXl: lerpDouble(spaceXl, other.spaceXl, t)!,
      space2xl: lerpDouble(space2xl, other.space2xl, t)!,
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t)!,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t)!,
      radiusLg: lerpDouble(radiusLg, other.radiusLg, t)!,
      radiusXl: lerpDouble(radiusXl, other.radiusXl, t)!,
      radiusPill: lerpDouble(radiusPill, other.radiusPill, t)!,
    );
  }

  /// Element-wise colour interpolation. Lists of different lengths hold their
  /// last entry rather than throwing mid-animation.
  static List<Color> _lerpColors(List<Color> a, List<Color> b, double t) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    final int length = math.max(a.length, b.length);
    return List<Color>.unmodifiable(
      List<Color>.generate(length, (int i) {
        final Color from = i < a.length ? a[i] : a.last;
        final Color to = i < b.length ? b[i] : b.last;
        return Color.lerp(from, to, t)!;
      }),
    );
  }
}
