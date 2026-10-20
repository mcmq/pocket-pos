import 'package:flutter/material.dart';

/// Color tokens from docs/design-system.md. Read them with `context.colors`.
/// Never hard-code hex values in widgets.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryDark,
    required this.onPrimary,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.surface,
    required this.surfaceTint,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.success,
    required this.successBg,
    required this.danger,
    required this.dangerBg,
    required this.warning,
    required this.warningBg,
    required this.categoryBadgeBg,
    required this.productTints,
    required this.scrim,
  });

  final Color primary;
  final Color primaryDark;
  final Color onPrimary;
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color surface;
  final Color surfaceTint;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;
  final Color success;
  final Color successBg;
  final Color danger;
  final Color dangerBg;
  final Color warning;
  final Color warningBg;
  final Color categoryBadgeBg;

  /// Soft pastel tints cycled behind product cards.
  final List<Color> productTints;
  final Color scrim;

  static const light = AppColors(
    primary: Color(0xFF0D5C6E),
    primaryDark: Color(0xFF0A4757),
    onPrimary: Color(0xFFFFFFFF),
    backgroundTop: Color(0xFFDCEDF0),
    backgroundBottom: Color(0xFFF3F8F9),
    surface: Color(0xFFFFFFFF),
    surfaceTint: Color(0xFFEEF6F7),
    outline: Color(0xFFD6E6E9),
    textPrimary: Color(0xFF1B2B30),
    // #6B7C80 is ~4.3:1 on white; darkened slightly to reach 4.5:1.
    textSecondary: Color(0xFF627377),
    success: Color(0xFF2E9E6A),
    successBg: Color(0xFFE3F5EC),
    danger: Color(0xFFE0464B),
    dangerBg: Color(0xFFFDE8E8),
    warning: Color(0xFFB7791F),
    warningBg: Color(0xFFFDF3E1),
    categoryBadgeBg: Color(0xFFE3F1F3),
    productTints: [
      Color(0xFFEAF6EA),
      Color(0xFFFDF0E6),
      Color(0xFFFCEBEF),
      Color(0xFFEAF2FB),
      Color(0xFFF3EEFB),
      Color(0xFFFBF7E4),
    ],
    scrim: Color(0x66000000),
  );

  static const dark = AppColors(
    primary: Color(0xFF2B8A9E),
    primaryDark: Color(0xFF1F6F80),
    onPrimary: Color(0xFFFFFFFF),
    backgroundTop: Color(0xFF0F1E22),
    backgroundBottom: Color(0xFF14282D),
    surface: Color(0xFF1A3036),
    surfaceTint: Color(0xFF223C43),
    outline: Color(0xFF2A454C),
    textPrimary: Color(0xFFE6F0F2),
    textSecondary: Color(0xFF9DB1B5),
    success: Color(0xFF4CC08A),
    successBg: Color(0xFF1C3A2E),
    danger: Color(0xFFF06A6E),
    dangerBg: Color(0xFF3D2224),
    warning: Color(0xFFE0A84A),
    warningBg: Color(0xFF3A3020),
    categoryBadgeBg: Color(0xFF223C43),
    productTints: [
      Color(0xFF1F3A33),
      Color(0xFF3A2F26),
      Color(0xFF3A2A30),
      Color(0xFF233345),
      Color(0xFF2E2A40),
      Color(0xFF38352A),
    ],
    scrim: Color(0x99000000),
  );

  Color tintFor(String key) =>
      productTints[key.hashCode.abs() % productTints.length];

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: l(primary, other.primary),
      primaryDark: l(primaryDark, other.primaryDark),
      onPrimary: l(onPrimary, other.onPrimary),
      backgroundTop: l(backgroundTop, other.backgroundTop),
      backgroundBottom: l(backgroundBottom, other.backgroundBottom),
      surface: l(surface, other.surface),
      surfaceTint: l(surfaceTint, other.surfaceTint),
      outline: l(outline, other.outline),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      success: l(success, other.success),
      successBg: l(successBg, other.successBg),
      danger: l(danger, other.danger),
      dangerBg: l(dangerBg, other.dangerBg),
      warning: l(warning, other.warning),
      warningBg: l(warningBg, other.warningBg),
      categoryBadgeBg: l(categoryBadgeBg, other.categoryBadgeBg),
      productTints: [
        for (var i = 0; i < productTints.length; i++)
          l(productTints[i], other.productTints[i]),
      ],
      scrim: l(scrim, other.scrim),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
