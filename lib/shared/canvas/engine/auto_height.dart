// lib/shared/canvas/engine/auto_height.dart
//
// Content-driven height measurement — single source of truth for sizing
// text + table sections. Pure Dart (TextPainter), headless-safe (canvas,
// PDF, thumbnails share the numbers). Biased slightly TALL: over-reserving
// leaves a small gap (harmless); under-reserving causes overlap (the bug).

import 'package:flutter/material.dart';
import '../../models/table_data.dart';

class AutoHeight {
  // ── Text tuning ──
  static const double textLineHeight = 1.5;
  static const double paragraphSpacing = 8.0;
  static const double textVPad = 10.0;
  static const double defaultFontSize = 11.0;

  // ── Table tuning — MUST mirror TableSectionRenderer ──
  static const double headerVPad = 6, cellVPad = 5, cellHPad = 8;
  static const double tableBorder = 0.5;
  static const double rowSafety = 3.0;   // per-row cushion
  static const double tableSafety = 4.0; // overall cushion

  /// Rendered height of quill delta ops at [width].
  static double measureText(
      List<dynamic> ops,
      double width, {
        String globalFont = 'OpenSans',
        double globalFontSize = 12,
      }) {
    if (ops.isEmpty || width <= 0) return 0;

    final paragraphs = <List<InlineSpan>>[];
    var current = <InlineSpan>[];
    void flush() { paragraphs.add(current); current = <InlineSpan>[]; }

    for (final raw in ops) {
      if (raw is! Map) continue;
      final insert = raw['insert'];
      if (insert is! String) continue;
      final attrs = (raw['attributes'] as Map?)?.cast<String, dynamic>();
      double size = globalFontSize;
      if (attrs?['size'] != null) {
        size = double.tryParse(attrs!['size'].toString()) ?? globalFontSize;
      }
      final style = TextStyle(
        fontFamily: (attrs?['font'] as String?) ?? globalFont,
        fontSize: size,
        height: textLineHeight,
        fontWeight: attrs?['bold'] == true ? FontWeight.bold : FontWeight.normal,
        fontStyle: attrs?['italic'] == true ? FontStyle.italic : FontStyle.normal,
      );
      final parts = insert.split('\n');
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) current.add(TextSpan(text: parts[i], style: style));
        if (i < parts.length - 1) flush();
      }
    }
    if (current.isNotEmpty) flush();
    if (paragraphs.isEmpty) return 0;

    double total = 0;
    for (final spans in paragraphs) {
      if (spans.isEmpty) {
        total += defaultFontSize * textLineHeight;
      } else {
        final tp = TextPainter(
          text: TextSpan(children: spans),
          textDirection: TextDirection.ltr,
          maxLines: null,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: width);
        total += tp.height;
      }
    }
    total += (paragraphs.length - 1).clamp(0, 9999) * paragraphSpacing;
    return total + textVPad;
  }

  /// True table height. Mirrors TableSectionRenderer's columns + padding,
  /// uses intrinsic font line height (no forced multiplier), biased tall.
  static double measureTable(TableData data, double width) {
    final cols = data.columnCount;
    if (cols == 0 || data.headers.isEmpty || width <= 0) return 0;

    final usable = width - (cols + 1) * tableBorder;
    final colW = usable / cols;
    // -2px so we never under-count wrapped lines from rounding.
    final contentW = (colW - cellHPad * 2 - 2).clamp(1.0, double.infinity);

    double rowH(List<String> cells, TextStyle style, double vpad) {
      double maxH = 0;
      for (int c = 0; c < cols; c++) {
        final txt = c < cells.length ? cells[c] : '';
        final tp = TextPainter(
          text: TextSpan(text: txt.isEmpty ? ' ' : txt, style: style),
          textDirection: TextDirection.ltr,
          maxLines: null,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: contentW);
        if (tp.height > maxH) maxH = tp.height;
      }
      return maxH + vpad * 2 + rowSafety;
    }

    double total = (data.rowCount + (data.showHeader ? 1 : 0) + 1) * tableBorder;
    if (data.showHeader) {
      total += rowH(
        data.headers,
        TextStyle(fontSize: data.fontSize, fontWeight: FontWeight.w600, fontFamily: 'OpenSans'),
        headerVPad,
      );
    }
    final cellStyle = TextStyle(fontSize: data.fontSize, fontFamily: 'OpenSans');
    for (int r = 0; r < data.rowCount; r++) {
      total += rowH(data.rows[r], cellStyle, cellVPad);
    }
    return total + tableSafety;
  }
}