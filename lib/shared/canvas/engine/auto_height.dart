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

  /// Measures each paragraph's height separately, returning a list parallel
  /// to the paragraphs in [ops]. Used by the reflow engine to find where to
  /// split a section across a page boundary. Mirrors measureText exactly so
  /// the numbers agree.
  static List<ParaMeasure> measureParagraphs(
      List<dynamic> ops,
      double width, {
        String globalFont = 'OpenSans',
        double globalFontSize = 12,
      }) {
    if (ops.isEmpty || width <= 0) return const [];

    // Build paragraphs, but ALSO remember which ops belong to each paragraph
    // so we can split the delta later at the same boundary.
    final paragraphs = <List<InlineSpan>>[];
    final paraOps = <List<Map<String, dynamic>>>[]; // ops per paragraph
    var current = <InlineSpan>[];
    var currentOps = <Map<String, dynamic>>[];
    void flush() {
      paragraphs.add(current);
      paraOps.add(currentOps);
      current = <InlineSpan>[];
      currentOps = <Map<String, dynamic>>[];
    }

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
        if (parts[i].isNotEmpty) {
          current.add(TextSpan(text: parts[i], style: style));
          currentOps.add({
            'insert': parts[i],
            if (attrs != null) 'attributes': Map<String, dynamic>.from(attrs),
          });
        }
        if (i < parts.length - 1) flush();
      }
    }
    if (current.isNotEmpty || currentOps.isNotEmpty) flush();

    final result = <ParaMeasure>[];
    for (int p = 0; p < paragraphs.length; p++) {
      final spans = paragraphs[p];
      double h;
      if (spans.isEmpty) {
        h = defaultFontSize * textLineHeight;
      } else {
        final tp = TextPainter(
          text: TextSpan(children: spans),
          textDirection: TextDirection.ltr,
          maxLines: null,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: width);
        h = tp.height;
      }
      result.add(ParaMeasure(height: h, ops: paraOps[p]));
    }
    return result;
  }

  /// Splits a list of paragraph measures into two delta-op lists at [splitIndex]
  /// (paragraphs [0, splitIndex) go to the first; the rest to the second).
  /// Each returned list is a valid Quill delta with plain '\n' separators.
  static (List<Map<String, dynamic>>, List<Map<String, dynamic>>) splitParagraphs(
      List<ParaMeasure> paras, int splitIndex) {
    List<Map<String, dynamic>> build(Iterable<ParaMeasure> ps) {
      final ops = <Map<String, dynamic>>[];
      final list = ps.toList();
      for (int i = 0; i < list.length; i++) {
        for (final op in list[i].ops) {
          ops.add(Map<String, dynamic>.from(op));
        }
        ops.add({'insert': '\n'}); // plain newline between paragraphs
      }
      if (ops.isEmpty) ops.add({'insert': '\n'});
      return ops;
    }
    final first = build(paras.take(splitIndex));
    final second = build(paras.skip(splitIndex));
    return (first, second);
  }

  /// Measures each table row's height separately (header first if shown),
  /// returning a list parallel to the rows. Used by the reflow engine to
  /// split a table across a page boundary. Mirrors measureTable's math.
  static List<double> measureTableRows(TableData data, double width) {
    final cols = data.columnCount;
    if (cols == 0 || data.headers.isEmpty || width <= 0) return const [];

    final usable = width - (cols + 1) * tableBorder;
    final colW = usable / cols;
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
      return maxH + vpad * 2 + rowSafety + tableBorder;
    }

    final result = <double>[];
    if (data.showHeader) {
      result.add(rowH(
        data.headers,
        TextStyle(fontSize: data.fontSize, fontWeight: FontWeight.w600, fontFamily: 'OpenSans'),
        headerVPad,
      ));
    }
    final cellStyle = TextStyle(fontSize: data.fontSize, fontFamily: 'OpenSans');
    for (int r = 0; r < data.rowCount; r++) {
      result.add(rowH(data.rows[r], cellStyle, cellVPad));
    }
    return result;
  }
}

class ParaMeasure {
  final double height;
  final List<Map<String, dynamic>> ops;
  const ParaMeasure({required this.height, required this.ops});
}