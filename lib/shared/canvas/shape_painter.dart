// lib/features/cv/view/shape_painter.dart

import 'package:flutter/material.dart';

class ShapePainter extends CustomPainter {
  final List<Offset> vertices;
  final Color fillColor, strokeColor;
  final double strokeWidth;

  ShapePainter({
    required this.vertices,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;
    final path = Path();
    path.moveTo(
        vertices.first.dx * size.width, vertices.first.dy * size.height);
    for (final v in vertices.skip(1)) {
      path.lineTo(v.dx * size.width, v.dy * size.height);
    }
    path.close();

    if (fillColor != Colors.transparent) {
      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(ShapePainter old) =>
      old.vertices != vertices ||
          old.fillColor != fillColor ||
          old.strokeColor != strokeColor ||
          old.strokeWidth != strokeWidth;
}

class MarqueePainter extends CustomPainter {
  final Offset start, end;
  MarqueePainter(this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0x192196F3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFF2196F3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(MarqueePainter old) =>
      old.start != start || old.end != end;
}