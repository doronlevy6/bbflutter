import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Color Palette
  static const Color primaryGreen = Color(0xFF0C7A4A); // Emerald
  static const Color accentGreen = Color(0xFF4ADE80); // Fresh mint accent
  static const Color backgroundLight = Color(0xFFF4F7F5);
  static const Color surfaceWhite = Colors.white;
  static const Color surfaceMuted = Color(0xFFF0F2F0);
  static const Color textPrimary = Color(0xFF12251C);
  static const Color textSecondary = Color(0xFF5D6B64);
  static const Color outlineSoft = Color(0xFFE1E6E3);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: accentGreen,
        tertiary: Color(0xFF0F5132),
        background: backgroundLight,
        surface: surfaceWhite,
        surfaceVariant: surfaceMuted,
        outline: outlineSoft,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
      ),
      scaffoldBackgroundColor: backgroundLight,
      
      // Typography
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        displayLarge: GoogleFonts.poppins(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: GoogleFonts.poppins(
          fontSize: 16,
          color: textPrimary,
        ),
        bodyMedium: GoogleFonts.poppins(
          fontSize: 14,
          color: textSecondary,
        ),
      ),

      // AppBar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          elevation: 4,
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryGreen,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGreen,
          side: BorderSide(color: outlineSoft, width: 1.2),
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primaryGreen, width: 1.8),
        ),
        labelStyle: TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
        hintStyle: TextStyle(color: textSecondary.withOpacity(0.7)),
        prefixIconColor: primaryGreen,
        suffixIconColor: textSecondary,
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.all(8),
      ),
      
      // Icon Theme
      iconTheme: IconThemeData(
        color: primaryGreen,
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        dense: false,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        tileColor: Colors.white,
        selectedTileColor: primaryGreen.withOpacity(0.08),
        iconColor: primaryGreen,
        textColor: textPrimary,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        disabledColor: surfaceMuted,
        selectedColor: primaryGreen.withOpacity(0.12),
        secondarySelectedColor: primaryGreen.withOpacity(0.2),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(color: textPrimary),
        brightness: Brightness.light,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: outlineSoft),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: outlineSoft,
        thickness: 1,
        space: 24,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: Colors.black.withOpacity(0.9),
        contentTextStyle: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: GoogleFonts.poppins(color: Colors.white),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
