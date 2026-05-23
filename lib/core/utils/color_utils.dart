import 'package:flutter/material.dart';

class ColorUtils {
  ColorUtils._();

  static Color fromHex(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  static String toHex(Color color) {
    final r = color.r.toInt().toRadixString(16).padLeft(2, '0');
    final g = color.g.toInt().toRadixString(16).padLeft(2, '0');
    final b = color.b.toInt().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b'.toUpperCase();
  }
}