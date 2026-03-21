import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Midnight Ocean Core Colors
  static const Color background = Color(0xFF0F111A);
  static const Color surface = Color(0xFF1C1E2C);
  static const Color surfaceLight = Color(0xFF2A2D40);

  // Vibrant Accents
  static const Color primary = Color(0xFF0F2F6A);   // Deep Navy (Brand)
  static const Color primaryLight = Color(0xFF818CF8); // Indigo for Dark Mode
  static const Color secondary = Color(0xFFEC4899); // Pink
  static const Color tertiary = Color(0xFF06B6D4); // Cyan

  // Text Colors
  static const Color textHighEmphasis = Color(0xFFF8FAFC);
  static const Color textMediumEmphasis = Color(0xFF94A3B8);
  static const Color textLowEmphasis = Color(0xFF475569);

  // Borders
  static const Color borderOverlay = Color(0x33FFFFFF);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassGradient = LinearGradient(
    colors: [Color(0x22FFFFFF), Color(0x05FFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primaryLight,
        secondary: secondary,
        tertiary: tertiary,
        surface: surface,
        onSurface: textHighEmphasis,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: textHighEmphasis,
            ),
            displayMedium: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: textHighEmphasis,
            ),
            displaySmall: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: textHighEmphasis,
            ),
            headlineLarge: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              color: textHighEmphasis,
            ),
            headlineMedium: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              color: textHighEmphasis,
            ),
            headlineSmall: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              color: textHighEmphasis,
            ),
            titleLarge: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: textHighEmphasis,
            ),
            titleMedium: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: textHighEmphasis,
            ),
            titleSmall: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: textHighEmphasis,
            ),
            bodyLarge: GoogleFonts.inter(color: textHighEmphasis),
            bodyMedium: GoogleFonts.inter(color: textHighEmphasis),
            bodySmall: GoogleFonts.inter(color: textMediumEmphasis),
            labelLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: textHighEmphasis,
            ),
            labelMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: textMediumEmphasis,
            ),
            labelSmall: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: textMediumEmphasis,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: textHighEmphasis),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textHighEmphasis,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: primary.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textHighEmphasis,
          side: const BorderSide(color: borderOverlay, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface.withValues(alpha: 0.5),
        hintStyle: GoogleFonts.inter(color: textMediumEmphasis),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderOverlay),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderOverlay),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        prefixIconColor: textMediumEmphasis,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: borderOverlay, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 20,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  // Light Theme Colors
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceLight = Color(0xFFF1F5F9);
  static const Color lightTextHighEmphasis = Color(0xFF0F172A);
  static const Color lightTextMediumEmphasis = Color(0xFF64748B);
  static const Color lightBorderOverlay = Color(0x1A000000);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
        surface: lightSurface,
        onSurface: lightTextHighEmphasis,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: lightTextHighEmphasis,
            ),
            displayMedium: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: lightTextHighEmphasis,
            ),
            displaySmall: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              color: lightTextHighEmphasis,
            ),
            headlineLarge: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              color: lightTextHighEmphasis,
            ),
            headlineMedium: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              color: lightTextHighEmphasis,
            ),
            headlineSmall: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              color: lightTextHighEmphasis,
            ),
            titleLarge: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: lightTextHighEmphasis,
            ),
            titleMedium: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: lightTextHighEmphasis,
            ),
            titleSmall: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: lightTextHighEmphasis,
            ),
            bodyLarge: GoogleFonts.inter(color: lightTextHighEmphasis),
            bodyMedium: GoogleFonts.inter(color: lightTextHighEmphasis),
            bodySmall: GoogleFonts.inter(color: lightTextMediumEmphasis),
            labelLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: lightTextHighEmphasis,
            ),
            labelMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: lightTextMediumEmphasis,
            ),
            labelSmall: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: lightTextMediumEmphasis,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: lightTextHighEmphasis),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: lightTextHighEmphasis,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: primary.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightTextHighEmphasis,
          side: const BorderSide(color: lightBorderOverlay, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurfaceLight,
        hintStyle: GoogleFonts.inter(color: lightTextMediumEmphasis),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: lightBorderOverlay),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: lightBorderOverlay),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        prefixIconColor: lightTextMediumEmphasis,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: lightBorderOverlay, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        elevation: 20,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

// Performance-friendly Ambient Glow (Replacing expensive BackdropFilter)
class AmbientGlow extends StatelessWidget {
  final Color color;
  final double radius;

  const AmbientGlow({super.key, required this.color, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
          stops: const [0.1, 1.0],
        ),
      ),
    );
  }
}

// Glassmorphic Card Container Widget
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius? borderRadius;
  final double blur;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.borderRadius,
    this.blur = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    var bRadius = borderRadius ?? BorderRadius.circular(24);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: context.surfaceLightColor,
        borderRadius: bRadius,
        border: Border.all(color: context.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: bRadius,
        child: Container(
          decoration: const BoxDecoration(gradient: AppTheme.glassGradient),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Convenience extension to resolve theme-aware colors from any widget.
///
/// Usage: `context.bg` instead of `AppTheme.background`
extension ThemeColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bg => Theme.of(this).scaffoldBackgroundColor;
  Color get surfaceColor => Theme.of(this).colorScheme.surface;
  Color get surfaceLightColor =>
      isDark ? AppTheme.surfaceLight : AppTheme.lightSurfaceLight;
  Color get textHigh => Theme.of(this).colorScheme.onSurface;
  Color get textMed =>
      isDark ? AppTheme.textMediumEmphasis : AppTheme.lightTextMediumEmphasis;
  Color get textLow =>
      isDark ? AppTheme.textLowEmphasis : const Color(0xFF94A3B8);
  Color get border =>
      isDark ? AppTheme.borderOverlay : AppTheme.lightBorderOverlay;
  Color get primary => Theme.of(this).colorScheme.primary;
  Color get onPrimary => Theme.of(this).colorScheme.onPrimary;
  Color get secondary => Theme.of(this).colorScheme.secondary;
  Color get accent => Theme.of(this).colorScheme.tertiary;
  Color get onAccent => Colors.white;
  Color get textSecondary => textMed;
  Color get dividerColor => isDark ? border : Colors.grey.shade200;
}
