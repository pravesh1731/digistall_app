import 'package:flutter/material.dart';

/// Design tokens ported from the admin website's `new_theme.css`
/// (admin.digistall.in), so the app and the website look the same.
class DS {
  DS._();

  static const ink = Color(0xFF06302F);
  static const inkShadow = Color(0xFF021716);
  static const teal = Color(0xFF0E8A87);
  static const tealSoft = Color(0xFFDCEFEC);
  static const tealBright = Color(0xFF12A09C);
  static const awning = Color(0xFFF0533C);
  static const marigold = Color(0xFFFFB424);
  static const marigoldShadow = Color(0xFFB97F00);
  static const paper = Color(0xFFF2F8F7);
  static const backdrop = Color(0xFFE3EFED);
  static const muted = Color(0xFF4B6A69);
  static const line = Color(0xFFCFE3E0);
  static const green = Color(0xFF1FB55A);
  static const red = Color(0xFFD32F2F);

  // Tints used for icon tiles and placeholders.
  static const tintYellow = Color(0xFFFFE9B8);
  static const tintYellowFg = Color(0xFF9A6400);
  static const tintCoral = Color(0xFFFFD9D2);
  static const tintViolet = Color(0xFFE6E4FF);
  static const tintVioletFg = Color(0xFF4B45C9);
  static const tints = [tintYellow, tintCoral, tealSoft];

  static const display = 'Bricolage';
  static const body = 'Hind';

  /// Headline text (Bricolage Grotesque, falls back to Hind for Hindi).
  static TextStyle h(double size, {Color color = ink, FontWeight weight = FontWeight.w800}) => TextStyle(
        fontFamily: display,
        fontFamilyFallback: const [body],
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.02 * size,
        height: 1.12,
      );

  static TextStyle t(double size, {Color color = ink, FontWeight weight = FontWeight.w400, double? height}) => TextStyle(
        fontFamily: body,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height ?? 1.35,
      );

  static TextStyle mutedText([double size = 15]) => t(size, color: muted);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: body,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        secondary: marigold,
        surface: paper,
        error: awning,
      ),
      scaffoldBackgroundColor: paper,
      splashFactory: InkRipple.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: body, bodyColor: ink, displayColor: ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: teal),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: t(15, color: Colors.white, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: ink, width: 2),
        ),
        titleTextStyle: h(20),
        contentTextStyle: t(15, color: muted),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: teal),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? green : const Color(0xFFB8CCCA)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
