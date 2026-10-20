import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spacing scale and radii from docs/design-system.md.
abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// Horizontal screen padding.
  static const screen = 16.0;
}

abstract final class AppRadius {
  static const input = 12.0;
  static const card = 16.0;
  static const sheet = 28.0;
  static const pill = 999.0;
}

/// Shadow used only on the floating bottom bar and bottom sheets.
const appFloatingShadow = [
  BoxShadow(color: Color(0x0F000000), blurRadius: 24, offset: Offset(0, 8)),
];

abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.primary,
      brightness: brightness,
    ).copyWith(
      primary: c.primary,
      onPrimary: c.onPrimary,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      outline: c.outline,
      outlineVariant: c.outline,
      error: c.danger,
    );

    const tabular = [FontFeature.tabularFigures()];
    final text = TextTheme(
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: c.textPrimary),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: c.textPrimary),
      titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textPrimary),
      bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: c.textSecondary),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: c.textSecondary),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.textPrimary),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: c.textSecondary),
      // `amount` style: use headlineSmall (24) / titleSmall-sized variants via
      // AppText.amount below.
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
        fontFeatures: tabular,
      ),
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      borderSide: BorderSide(color: c.outline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.backgroundBottom,
      textTheme: text,
      extensions: [c],
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        hintStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        labelStyle: TextStyle(color: c.textSecondary, fontSize: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.primary, width: 1.4),
        ),
        errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.danger)),
        focusedErrorBorder:
            inputBorder.copyWith(borderSide: BorderSide(color: c.danger, width: 1.4)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          minimumSize: const Size(64, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: c.surface,
          foregroundColor: c.textPrimary,
          minimumSize: const Size(64, 48),
          shape: const StadiumBorder(),
          side: BorderSide(color: c.outline),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        shape: const StadiumBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.textPrimary,
        contentTextStyle: TextStyle(color: c.surface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.input)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onPrimary : c.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceTint,
        ),
        trackOutlineColor: WidgetStatePropertyAll(c.outline),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.input)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

/// Extra text styles not covered by [TextTheme].
abstract final class AppText {
  /// Prices, totals and KPI values, with tabular figures.
  static TextStyle amount(BuildContext context, {double size = 15, Color? color}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? context.colors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
