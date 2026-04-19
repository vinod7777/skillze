import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Midnight Ocean Core Colors
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF000000);
  static const Color surfaceLight = Color(0xFF151515);

  // Vibrant Accents
  static const Color primary = Color(0xFF0F2F6A);   // Deep Navy (Brand for light)
  static const Color primaryLight = Color(0xFFFFFFFF); // White for Dark Mode
  static const Color secondary = Color(0xFFFFFFFF); // White for Dark Mode
  static const Color tertiary = Color(0xFFFFFFFF); // White for Dark Mode

  // Text Colors (Dark Mode)
  static const Color textHighEmphasis = Color(0xFFFFFFFF);
  static const Color textMediumEmphasis = Color(0xFFA3A3A3);
  static const Color textLowEmphasis = Color(0xFF666666);

  // Borders (Dark Mode)
  static final Color borderOverlay = const Color(0xFFFFFFFF).withValues(alpha: 0.15);

  // Gradients
  // Radius Constants
  static const double cardRadius = 12.0;
  static const double buttonRadius = 10.0;
  static const double inputRadius = 10.0;
  static const double sheetRadius = 16.0;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Colors.white, Color(0xFFAAAAAA)],
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
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: Colors.white,
        onSecondary: Colors.black,
        tertiary: Colors.white,
        surface: surface,
        onSurface: textHighEmphasis,
        onSurfaceVariant: textMediumEmphasis,
        outline: textLowEmphasis,
        error: Colors.white,
        onError: Colors.black,
        surfaceContainer: surfaceLight,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textHighEmphasis).copyWith(inherit: true),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textHighEmphasis).copyWith(inherit: true),
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: textHighEmphasis).copyWith(inherit: true),
        headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: textHighEmphasis).copyWith(inherit: true),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: textHighEmphasis).copyWith(inherit: true),
        headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: textHighEmphasis).copyWith(inherit: true),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: textHighEmphasis).copyWith(inherit: true),
        titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: textHighEmphasis).copyWith(inherit: true),
        titleSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: textHighEmphasis).copyWith(inherit: true),
        bodyLarge: GoogleFonts.inter(color: textHighEmphasis).copyWith(inherit: true),
        bodyMedium: GoogleFonts.inter(color: textHighEmphasis).copyWith(inherit: true),
        bodySmall: GoogleFonts.inter(color: textMediumEmphasis).copyWith(inherit: true),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textHighEmphasis).copyWith(inherit: true),
        labelMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textMediumEmphasis).copyWith(inherit: true),
        labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textLowEmphasis).copyWith(inherit: true),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: textHighEmphasis),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textHighEmphasis,
        ).copyWith(inherit: true),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: Colors.black, // Black text on white buttons for dark theme
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16).copyWith(inherit: true),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textHighEmphasis,
          side: BorderSide(color: textMediumEmphasis.withValues(alpha: 0.5), width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16).copyWith(inherit: true),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight, // Changed from surface to surfaceLight for contrast against pure black
        hintStyle: GoogleFonts.inter(color: textMediumEmphasis, fontSize: 14).copyWith(inherit: true),
        labelStyle: GoogleFonts.inter(color: textMediumEmphasis).copyWith(inherit: true),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: BorderSide(color: borderOverlay)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(inputRadius), borderSide: const BorderSide(color: Colors.redAccent)),
        prefixIconColor: textMediumEmphasis,
        suffixIconColor: textMediumEmphasis,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: borderOverlay, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: background,
        elevation: 20,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: textLowEmphasis.withValues(alpha: 0.2),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: GoogleFonts.inter(color: textHighEmphasis, fontWeight: FontWeight.w600, fontSize: 16).copyWith(inherit: true),
        subtitleTextStyle: GoogleFonts.inter(color: textMediumEmphasis, fontSize: 14).copyWith(inherit: true),
        iconColor: textMediumEmphasis,
      ),
      iconTheme: const IconThemeData(color: textMediumEmphasis),
      primaryIconTheme: const IconThemeData(color: primaryLight),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Colors.white,
        contentTextStyle: const TextStyle(color: Color(0xFF0F2F6A), fontWeight: FontWeight.bold),
        actionTextColor: const Color(0xFF0F2F6A),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
  static const Color lightTextHighEmphasis = Color(0xFF0F2F6A);
  static const Color lightTextMediumEmphasis = Color(0xFF64748B);
  static const Color lightBorderOverlay = Color(0x1A000000);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF0F2F6A),
        onPrimary: Colors.white,
        secondary: Color(0xFF0F2F6A),
        onSecondary: Colors.white,
        tertiary: Color(0xFF0F2F6A),
        onTertiary: Colors.white,
        surface: lightSurface,
        onSurface: Color(0xFF0F2F6A),
        onSurfaceVariant: Color(0xFF64748B),
        outline: Color(0xFF94A3B8),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: lightTextHighEmphasis).copyWith(inherit: true),
        displayMedium: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: lightTextHighEmphasis).copyWith(inherit: true),
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: lightTextHighEmphasis).copyWith(inherit: true),
        headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: lightTextHighEmphasis).copyWith(inherit: true),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: lightTextHighEmphasis).copyWith(inherit: true),
        headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: lightTextHighEmphasis).copyWith(inherit: true),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: lightTextHighEmphasis).copyWith(inherit: true),
        titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: lightTextHighEmphasis).copyWith(inherit: true),
        titleSmall: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: lightTextHighEmphasis).copyWith(inherit: true),
        bodyLarge: GoogleFonts.inter(color: lightTextHighEmphasis).copyWith(inherit: true),
        bodyMedium: GoogleFonts.inter(color: lightTextHighEmphasis).copyWith(inherit: true),
        bodySmall: GoogleFonts.inter(color: lightTextMediumEmphasis).copyWith(inherit: true),
        labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, color: lightTextHighEmphasis).copyWith(inherit: true),
        labelMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, color: lightTextMediumEmphasis).copyWith(inherit: true),
        labelSmall: GoogleFonts.inter(fontWeight: FontWeight.w600, color: lightTextMediumEmphasis).copyWith(inherit: true),
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
        ).copyWith(inherit: true),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: primary.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16).copyWith(inherit: true),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightTextHighEmphasis,
          side: const BorderSide(color: lightBorderOverlay, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(buttonRadius)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16).copyWith(inherit: true),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurfaceLight,
        hintStyle: GoogleFonts.inter(color: lightTextMediumEmphasis).copyWith(inherit: true),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        prefixIconColor: lightTextMediumEmphasis,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: lightBorderOverlay, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        elevation: 20,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(sheetRadius)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: GoogleFonts.inter(color: lightTextHighEmphasis, fontWeight: FontWeight.w600, fontSize: 16).copyWith(inherit: true),
        subtitleTextStyle: GoogleFonts.inter(color: lightTextMediumEmphasis, fontSize: 14).copyWith(inherit: true),
        iconColor: lightTextMediumEmphasis,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Colors.white,
        contentTextStyle: const TextStyle(color: Color(0xFF0F2F6A), fontWeight: FontWeight.bold),
        actionTextColor: const Color(0xFF0F2F6A),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    var bRadius = borderRadius ?? BorderRadius.circular(8);
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
  Color get textMed => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get textLow => Theme.of(this).colorScheme.outline;
  Color get border => isDark ? AppTheme.borderOverlay : AppTheme.lightBorderOverlay;
  Color get primary => Theme.of(this).colorScheme.primary;
  Color get onPrimary => Theme.of(this).colorScheme.onPrimary;
  Color get secondary => Theme.of(this).colorScheme.secondary;
  Color get accent => Theme.of(this).colorScheme.tertiary;
  Color get onAccent => Colors.white;
  Color get textSecondary => textMed;
  Color get dividerColor => Theme.of(this).dividerTheme.color ?? (isDark ? border : Colors.grey.shade200);
}
