import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // PRIMARY
  static const Color lavenderBlush = Color(0xFFFFF1F5);
  static const Color petalFrost    = Color(0xFFFFE4EC);
  static const Color prussianBlue  = Color(0xFF0F172A);
  static const Color darkRaspberry = Color(0xFF831843);
  static const Color warmGrey = Color(0xFFF8F5F2);

  // SECONDARY
  static const Color almondSilk    = Color(0xFFC5AFA4);
  static const Color dustyRose     = Color(0xFFCC7E85);
  static const Color magentaBloom  = Color(0xFFCF4D6F);
  static const Color dustyMauve    = Color(0xFFA36D90);
  static const Color slateGrey     = Color(0xFF76818E);

  // UTILITY
  static const Color white         = Color(0xFFFFFFFF);
  static const Color success       = Color(0xFF2ECC71);
  static const Color error         = Color(0xFFE74C3C);

  static Color withAlpha(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }
}