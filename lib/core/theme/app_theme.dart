import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_fonts.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: AppFonts.poppins,
    scaffoldBackgroundColor: AppColors.lavenderBlush,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.darkRaspberry,
      primary: AppColors.darkRaspberry,
      secondary: AppColors.magentaBloom,
      surface: AppColors.white,
      error: AppColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.prussianBlue,
      foregroundColor: AppColors.white,
      elevation: 0,
      centerTitle: false,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.darkRaspberry,
        foregroundColor: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          fontFamily: AppFonts.poppins,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        minimumSize: const Size(double.infinity, 48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.almondSilk),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.almondSilk),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: AppColors.darkRaspberry,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      labelStyle: const TextStyle(
        color: AppColors.slateGrey,
        fontFamily: AppFonts.poppins,
        fontSize: 13,
      ),
      hintStyle: const TextStyle(
        color: AppColors.almondSilk,
        fontFamily: AppFonts.openSans,
        fontSize: 14,
      ),
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.bold,
        color: AppColors.prussianBlue,
        fontSize: 36,
      ),
      headlineLarge: TextStyle(
        fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.bold,
        color: AppColors.prussianBlue,
        fontSize: 28,
      ),
      headlineMedium: TextStyle(
        fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.bold,
        color: AppColors.prussianBlue,
        fontSize: 22,
      ),
      titleLarge: TextStyle(
        fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.w600,
        color: AppColors.prussianBlue,
        fontSize: 16,
      ),
      titleMedium: TextStyle(
        fontFamily: AppFonts.poppins,
        fontWeight: FontWeight.w500,
        color: AppColors.prussianBlue,
        fontSize: 14,
      ),
      bodyLarge: TextStyle(
        fontFamily: AppFonts.openSans,
        color: AppColors.prussianBlue,
        fontSize: 15,
      ),
      bodyMedium: TextStyle(
        fontFamily: AppFonts.openSans,
        color: AppColors.slateGrey,
        fontSize: 13,
      ),
      bodySmall: TextStyle(
        fontFamily: AppFonts.openSans,
        color: AppColors.slateGrey,
        fontSize: 12,
      ),
    ),
  );
}