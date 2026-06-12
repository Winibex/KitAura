// lib/shared/widgets/template_thumbnail.dart
//
// Renders a real miniature preview of a template JSON file.
// Uses CustomPainter to draw shapes and text — no QuillController,
// no flutter_quill import, no heavy dependencies.
//
// FIX: now reads the COLOR / SIZE / BOLD attributes from each delta op
// instead of guessing from the section's fill color. This makes the
// picker preview match the editor exactly (white-on-navy headers etc).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TemplateThumbnail extends StatefulWidget {
  final String? assetPath;
  final Map<String, dynamic>? json;
  final double width;
  final double height;
  final double borderRadius;
  final bool showShadow;

  const TemplateThumbnail({
    super.key,
    required this.assetPath,
    required this.width,
    required this.height,
    this.borderRadius = 8,
    this.showShadow = true,
  }) : json = null;

  const TemplateThumbnail.fromJson({
    super.key,
    required this.json,
    required this.width,
    required this.height,
    this.borderRadius = 8,
    this.showShadow = true,
  }) : assetPath = null;

  @override
  State<TemplateThumbnail> createState() => _TemplateThumbnailState();
}

class _TemplateThumbnailState extends State<TemplateThumbnail> {
  Map<String, dynamic>? _templateData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.json != null) {
      _templateData = widget.json;
      _loading = false;
    } else if (widget.assetPath != null) {
      _loadAsset();
    }
  }

  @override
  void didUpdateWidget(TemplateThumbnail old) {
    super.didUpdateWidget(old);
    // Reload if the source changed
    if (widget.assetPath != old.assetPath) {
      _loading = true;
      _loadAsset();
    } else if (widget.json != old.json && widget.json != null) {
      setState(() {
        _templateData = widget.json;
        _loading = false;
      });
    }
  }

  Future<void> _loadAsset() async {
    try {
      final jsonStr = await rootBundle.loadString(widget.assetPath!);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (mounted) setState(() { _templateData = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: widget.showShadow
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12, offset: const Offset(0, 4))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: _loading
            ? Container(color: const Color(0xFFF5F0EC))
            : _templateData != null
            ? CustomPaint(
          size: Size(widget.width, widget.height),
          painter: _TemplatePainter(
            templateData: _templateData!,
            canvasW: 595,
            canvasH: 842,
          ),
        )
            : Container(
          color: const Color(0xFFF5F0EC),
          child: const Center(
            child: Icon(Icons.description_outlined,
                color: Color(0xFFCCC0B5), size: 32),
          ),
        ),
      ),
    );
  }
}

// ─── PAINTER ─────────────────────────────────────────────────────────────

class _TemplatePainter extends CustomPainter {
  final Map<String, dynamic> templateData;
  final double canvasW;
  final double canvasH;

  _TemplatePainter({
    required this.templateData,
    required this.canvasW,
    required this.canvasH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / canvasW;
    final scaleY = size.height / canvasH;

    final bgColor = _parseColor(
        templateData['canvasBackground'] as String? ?? '#FFFFFF');
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bgColor,
    );

    final items = templateData['items'] as List<dynamic>? ?? [];
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final type = map['type'] as String? ?? '';
      final x = (map['x'] as num? ?? 0).toDouble() * scaleX;
      final y = (map['y'] as num? ?? 0).toDouble() * scaleY;
      final w = (map['w'] as num? ?? 0).toDouble() * scaleX;
      final h = (map['h'] as num? ?? 0).toDouble() * scaleY;
      final color = _parseColor(map['color'] as String? ?? '#CCCCCC');
      final borderColor =
      _parseColor(map['borderColor'] as String? ?? '#CCCCCC');
      final borderWidth =
      ((map['borderWidth'] as num? ?? 0).toDouble() * scaleX)
          .clamp(0.0, 4.0);

      switch (type) {
        case 'rectangle':
          _drawRect(canvas, x, y, w, h, color, borderColor, borderWidth);
        case 'line':
          _drawLine(canvas, x, y, w, borderColor, borderWidth.clamp(0.5, 3.0));
        case 'circle':
          _drawCircle(canvas, x, y, w, h, color, borderColor, borderWidth);
        case 'textSection':
          _drawText(canvas, map, x, y, w, h, scaleX, scaleY);
        case 'tableSection':
          _drawTable(canvas, map, x, y, w, h, scaleX, scaleY);
        case 'triangle':
          _drawTriangle(canvas, x, y, w, h, color, borderColor, borderWidth);
        case 'star':
          _drawStar(canvas, x, y, w, h, color);
        case 'diamond':
          _drawDiamond(canvas, x, y, w, h, color, borderColor, borderWidth);
        case 'icon':
          _drawCircle(canvas, x, y, w, h,
              const Color(0xFFE0D6CC), borderColor, 0);
        case 'imageBox':
          _drawRect(canvas, x, y, w, h,
              const Color(0xFFEDE8E3), const Color(0xFFDDD5CB), 0.5);
      }
    }
  }

  void _drawTable(Canvas canvas, Map<String, dynamic> map, double x, double y,
      double w, double h, double scaleX, double scaleY)
  {
    final tableDataRaw = map['tableData'] as Map<String, dynamic>?;
    if (tableDataRaw == null) {
      _drawPlaceholderLines(canvas, x, y, w, h, scaleY);
      return;
    }

    final headers = (tableDataRaw['headers'] as List?)?.cast<String>() ?? [];
    final rows = (tableDataRaw['rows'] as List?)
        ?.map((r) => (r as List).cast<String>())
        .toList() ??
        [];
    final headerBg =
    _parseColor(tableDataRaw['headerBgColor'] as String? ?? '#0F172A');
    final headerTextColor =
    _parseColor(tableDataRaw['headerTextColor'] as String? ?? '#FFFFFF');
    final cellTextColor =
    _parseColor(tableDataRaw['cellTextColor'] as String? ?? '#333333');
    final borderColor =
    _parseColor(tableDataRaw['borderColor'] as String? ?? '#E0E0E0');
    final showHeader = tableDataRaw['showHeader'] ?? true;

    if (headers.isEmpty) {
      _drawPlaceholderLines(canvas, x, y, w, h, scaleY);
      return;
    }

    final colCount = headers.length;
    final colW = w / colCount;
    final rowH = (5.5 * scaleY).clamp(4.0, 14.0);
    final fontSize = (9.0 * scaleY).clamp(2.0, 7.0);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = (0.5 * scaleX).clamp(0.2, 0.8);

    double curY = y;

    // Header row
    if (showHeader) {
      final headerRect = Rect.fromLTWH(x, curY, w, rowH);
      canvas.drawRect(headerRect, Paint()..color = headerBg);
      canvas.drawRect(headerRect, borderPaint);

      for (int c = 0; c < colCount; c++) {
        final tp = TextPainter(
          text: TextSpan(
            text: headers[c],
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: headerTextColor,
            ),
          ),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: colW - 2 * scaleX);
        tp.paint(canvas, Offset(x + c * colW + 1.5 * scaleX, curY + 1 * scaleY));
      }
      curY += rowH;
    }

    // Data rows
    for (int r = 0; r < rows.length && curY + rowH <= y + h; r++) {
      final rowBg = r % 2 == 0 ? const Color(0xFFFFFFFF) : const Color(0xFFF9F7F5);
      final rowRect = Rect.fromLTWH(x, curY, w, rowH);
      canvas.drawRect(rowRect, Paint()..color = rowBg);
      canvas.drawRect(rowRect, borderPaint);

      for (int c = 0; c < colCount && c < rows[r].length; c++) {
        final tp = TextPainter(
          text: TextSpan(
            text: rows[r][c],
            style: TextStyle(
              fontSize: fontSize,
              color: cellTextColor,
            ),
          ),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: colW - 2 * scaleX);
        tp.paint(canvas, Offset(x + c * colW + 1.5 * scaleX, curY + 1 * scaleY));
      }
      curY += rowH;
    }
  }


  void _drawRect(Canvas canvas, double x, double y, double w, double h,
      Color fill, Color border, double borderW)
  {
    final rect = Rect.fromLTWH(x, y, w, h);
    canvas.drawRect(rect, Paint()..color = fill);
    if (borderW > 0) {
      canvas.drawRect(
          rect,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderW);
    }
  }

  void _drawLine(Canvas canvas, double x, double y, double w,
      Color color, double strokeW)
  {
    canvas.drawLine(
      Offset(x, y),
      Offset(x + w, y),
      Paint()
        ..color = color
        ..strokeWidth = strokeW.clamp(0.3, 2.0),
    );
  }

  void _drawCircle(Canvas canvas, double x, double y, double w, double h,
      Color fill, Color border, double borderW)
  {
    final center = Offset(x + w / 2, y + h / 2);
    final radius = (w < h ? w : h) / 2;
    canvas.drawCircle(center, radius, Paint()..color = fill);
    if (borderW > 0) {
      canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderW);
    }
  }

  void _drawTriangle(Canvas canvas, double x, double y, double w, double h,
      Color fill, Color border, double borderW)
  {
    final path = Path()
      ..moveTo(x + w / 2, y)
      ..lineTo(x + w, y + h)
      ..lineTo(x, y + h)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    if (borderW > 0) {
      canvas.drawPath(
          path,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderW);
    }
  }

  void _drawStar(Canvas canvas, double x, double y, double w, double h,
      Color fill)
  {
    final cx = x + w / 2, cy = y + h / 2;
    final r = (w < h ? w : h) / 2;
    canvas.drawCircle(Offset(cx, cy), r * 0.6, Paint()..color = fill);
  }

  void _drawDiamond(Canvas canvas, double x, double y, double w, double h,
      Color fill, Color border, double borderW)
  {
    final path = Path()
      ..moveTo(x + w / 2, y)
      ..lineTo(x + w, y + h / 2)
      ..lineTo(x + w / 2, y + h)
      ..lineTo(x, y + h / 2)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    if (borderW > 0) {
      canvas.drawPath(
          path,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderW);
    }
  }

  // ── TEXT — reads per-op delta attributes (color/size/bold) ──────────

  void _drawText(Canvas canvas, Map<String, dynamic> map, double x, double y,
      double w, double h, double scaleX, double scaleY)
  {
    final delta = map['delta'] as List<dynamic>?;
    if (delta == null || delta.isEmpty) {
      _drawPlaceholderLines(canvas, x, y, w, h, scaleY);
      return;
    }

    // Build a list of "lines" where each line knows its own style,
    // pulled directly from the delta op attributes.
    final paintLines = <_PaintLine>[];

    for (final op in delta) {
      if (op is! Map || !op.containsKey('insert')) continue;
      final raw = op['insert'] as String? ?? '';
      if (raw.trim().isEmpty && !raw.contains('\n')) continue;

      final attrs = (op['attributes'] as Map?) ?? const {};

      // Parse the delta op's OWN color (this is the key fix)
      final colorHex = attrs['color'] as String?;
      Color textColor;
      if (colorHex != null) {
        textColor = _parseColor(colorHex);
      } else {
        // No explicit color → choose based on the SECTION's bg color
        final sectionBg = _parseColor(map['color'] as String? ?? '#FFFFFF');
        textColor = _isLight(sectionBg)
            ? const Color(0xFF333333)
            : const Color(0xFFEEEEEE);
      }

      // Parse size — scale down for thumbnail
      double rawSize = 11;
      final sz = attrs['size'];
      if (sz is String) {
        rawSize = double.tryParse(sz.replaceAll('pt', '')) ?? 11;
      } else if (sz is num) {
        rawSize = sz.toDouble();
      }
      final fontSize = (rawSize * scaleY).clamp(2.5, 11.0);

      final isBold = attrs['bold'] == true;

      // Split this op's text into lines (delta inserts can contain \n)
      final segments = raw.split('\n');
      for (final seg in segments) {
        if (seg.trim().isEmpty) continue;
        paintLines.add(_PaintLine(
          text: seg,
          color: textColor,
          fontSize: fontSize,
          bold: isBold,
        ));
      }
    }

    if (paintLines.isEmpty) {
      _drawPlaceholderLines(canvas, x, y, w, h, scaleY);
      return;
    }

    double lineY = y + 1 * scaleY;
    for (final pl in paintLines) {
      if (lineY > y + h) break;
      final tp = TextPainter(
        text: TextSpan(
          text: pl.text,
          style: TextStyle(
            fontSize: pl.fontSize,
            fontWeight: pl.bold ? FontWeight.w700 : FontWeight.w400,
            color: pl.color,
            height: 1.25,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: w - 3 * scaleX);
      tp.paint(canvas, Offset(x + 2 * scaleX, lineY));
      lineY += tp.height + 1.0 * scaleY;
    }
  }

  void _drawPlaceholderLines(
      Canvas canvas, double x, double y, double w, double h, double scaleY)
  {
    final paint = Paint()..color = const Color(0xFFE0D8D0);
    final lineH = 2.5 * scaleY;
    final gap = 4.0 * scaleY;
    double lineY = y + 4 * scaleY;

    for (int i = 0; i < 4 && lineY + lineH < y + h; i++) {
      final lineW = w * (i == 0 ? 0.6 : (i == 3 ? 0.4 : 0.85));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2 * scaleY, lineY, lineW, lineH),
          Radius.circular(lineH / 2),
        ),
        paint,
      );
      lineY += lineH + gap;
    }
  }

  bool _isLight(Color c) {
    return (c.r * 255.0 * 0.299 + c.g * 255.0 * 0.587 + c.b * 255.0 * 0.114) > 128;
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return const Color(0xFFCCCCCC);
  }

  @override
  bool shouldRepaint(_TemplatePainter old) =>
      templateData != old.templateData;
}

// Helper: a single line of text with its resolved style.
class _PaintLine {
  final String text;
  final Color color;
  final double fontSize;
  final bool bold;
  _PaintLine({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.bold,
  });
}