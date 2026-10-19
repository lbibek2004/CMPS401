import 'package:flutter/material.dart';

import 'app_color_scheme.dart';
import 'app_typography.dart';
import 'lionfit_tokens.dart';

export 'app_palette.dart' show BrandColors;
export 'app_typography.dart' show AppTypography;
export 'lionfit_tokens.dart' show LionFitTokens;

/// LionFit's two themes.
///
/// `main.dart` wires [light] and [dark] into `MaterialApp`; both carry the full
/// [ColorScheme], the type scale, component themes, and a registered
/// [LionFitTokens] extension, so a screen should not need per-screen styling.
///
/// Reaching for colour from a screen, in order of preference:
///
/// 1. `Theme.of(context).colorScheme` - surfaces, primary, error, outline.
/// 2. `LionFitTokens.of(context)` - intensity ramp, set types, chart series,
///    PR emphasis, status colours, spacing and radius scales.
/// 3. Nothing else. No hex literals outside `lib/core/theme/`, no
///    `Colors.green`.
abstract final class AppTheme {
  static ThemeData get light =>
      _build(AppColorSchemes.light, LionFitTokens.light);

  static ThemeData get dark => _build(AppColorSchemes.dark, LionFitTokens.dark);

  static ThemeData _build(ColorScheme scheme, LionFitTokens tokens) {
    final TextTheme text = AppTypography.textTheme(scheme);
    final bool isDark = scheme.brightness == Brightness.dark;

    // On a pure-black base a filled `#1A5634` button is only 2.42:1 against
    // the page, so its edge would be invisible even though its white label is
    // 8.66:1. The hairline restores the boundary at 6.02:1. The light theme
    // needs none: `#0B4022` on `#FFFFFF` is already 11.86:1.
    final BorderSide? brandFillEdge = isDark
        ? BorderSide(color: tokens.brandBorder)
        : null;

    final OutlinedBorder buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusMd),
    );
    final BorderRadius fieldRadius = BorderRadius.circular(tokens.radiusMd);
    final Color disabledFg = scheme.onSurface.withValues(alpha: 0.38);
    final Color disabledBg = scheme.onSurface.withValues(alpha: 0.12);

    InputBorder fieldBorder(Color color, double width) => OutlineInputBorder(
      borderRadius: fieldRadius,
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[tokens],
      visualDensity: VisualDensity.adaptivePlatformDensity,

      // Surface steps are explicit (see DarkPalette), so the tonal elevation
      // overlay would double-tint them.
      applyElevationOverlayColor: false,

      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      primaryIconTheme: IconThemeData(color: scheme.onPrimary),

      // ------------------------------------------------------------- app bar
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: tokens.spaceLg,
        titleTextStyle: text.titleLarge,
        toolbarTextStyle: text.bodyMedium,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        shape: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),

      // --------------------------------------------------------------- cards
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        // Zero margin: layouts own their spacing via the token scale.
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          // The fill step alone is ~1.1:1 on both bases. The edge is what
          // makes a card legible as a container; it is decorative, not
          // load-bearing, so outlineVariant is the right weight.
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      // ------------------------------------------------------------- buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          elevation: 0,
          side: brandFillEdge,
          shape: buttonShape,
          textStyle: text.labelLarge,
          minimumSize: const Size(64, 48),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spaceXl,
            vertical: tokens.spaceMd,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.brandText,
          disabledForegroundColor: disabledFg,
          side: BorderSide(color: tokens.brandBorder, width: 1.5),
          shape: buttonShape,
          textStyle: text.labelLarge,
          minimumSize: const Size(64, 48),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spaceXl,
            vertical: tokens.spaceMd,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.brandText,
          disabledForegroundColor: disabledFg,
          shape: buttonShape,
          textStyle: text.labelLarge,
          minimumSize: const Size(48, 44),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spaceMd,
            vertical: tokens.spaceSm,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundColor: tokens.brandText,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
          elevation: 0,
          side: BorderSide(color: scheme.outline),
          shape: buttonShape,
          textStyle: text.labelLarge,
          minimumSize: const Size(64, 48),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spaceXl,
            vertical: tokens.spaceMd,
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: isDark ? 0 : 2,
        focusElevation: isDark ? 0 : 4,
        hoverElevation: isDark ? 0 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          side: brandFillEdge ?? BorderSide.none,
        ),
      ),

      // ---------------------------------------------------------- text input
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.spaceLg,
          vertical: tokens.spaceLg - 2,
        ),
        // 1px at scheme.outline is 6.79:1 (dark) / 4.69:1 (light) against the
        // page, so an empty field is identifiable before it is focused.
        border: fieldBorder(scheme.outline, 1),
        enabledBorder: fieldBorder(scheme.outline, 1),
        // 2px brand stroke: 6.02:1 (dark) / 6.35:1 (light). A focus indicator
        // has to clear 3:1 against both the field fill and the page.
        focusedBorder: fieldBorder(tokens.brandBorder, 2),
        errorBorder: fieldBorder(scheme.error, 1),
        focusedErrorBorder: fieldBorder(scheme.error, 2),
        disabledBorder: fieldBorder(scheme.outlineVariant, 1),
        labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: tokens.brandText),
        // Full-strength onSurfaceVariant rather than a faded onSurface: hint
        // text still has to clear 4.5:1 (9.59:1 dark / 7.78:1 light).
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        errorMaxLines: 2,
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.disabled)) return disabledBg;
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll<Color>(scheme.onPrimary),
        side: BorderSide(color: scheme.outline, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.spaceXs),
        ),
      ),

      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll<Color>(scheme.outline),
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),

      // -------------------------------------------------------- containers
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(tokens.radiusXl),
          ),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: tokens.spaceLg,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: tokens.spaceLg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        disabledColor: disabledBg,
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        side: BorderSide(color: scheme.outline),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spaceMd,
          vertical: tokens.spaceSm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
      ),

      // ------------------------------------------------------- navigation
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: tokens.brandText,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall,
        indicatorColor: tokens.brandBorder,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: scheme.outlineVariant,
        overlayColor: WidgetStatePropertyAll<Color>(
          tokens.brandText.withValues(alpha: 0.08),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.brandText,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 6,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(tokens.radiusSm),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spaceMd,
          vertical: tokens.spaceSm,
        ),
      ),
    );
  }
}
