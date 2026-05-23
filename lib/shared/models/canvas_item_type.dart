import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

enum CanvasItemType {
  textSection, line, rectangle, circle, imageBox, icon,
  triangle, star, arrow, diamond, hexagon, skewedRectangle
}

enum ResizeHandle { topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }

// ─── TYPE CONVERSION ─────────────────────────────────────────────────────

CanvasItemType parseCanvasItemType(String raw) {
  switch (raw) {
    case 'textSection':      return CanvasItemType.textSection;
    case 'line':             return CanvasItemType.line;
    case 'rectangle':        return CanvasItemType.rectangle;
    case 'circle':           return CanvasItemType.circle;
    case 'imageBox':         return CanvasItemType.imageBox;
    case 'icon':             return CanvasItemType.icon;
    case 'triangle':         return CanvasItemType.triangle;
    case 'star':             return CanvasItemType.star;
    case 'arrow':            return CanvasItemType.arrow;
    case 'diamond':          return CanvasItemType.diamond;
    case 'hexagon':          return CanvasItemType.hexagon;
    case 'skewedRectangle':  return CanvasItemType.skewedRectangle;
    default:                 return CanvasItemType.rectangle;
  }
}

String canvasItemTypeToString(CanvasItemType type) {
  switch (type) {
    case CanvasItemType.textSection:     return 'textSection';
    case CanvasItemType.line:            return 'line';
    case CanvasItemType.rectangle:       return 'rectangle';
    case CanvasItemType.circle:          return 'circle';
    case CanvasItemType.imageBox:        return 'imageBox';
    case CanvasItemType.icon:            return 'icon';
    case CanvasItemType.triangle:        return 'triangle';
    case CanvasItemType.star:            return 'star';
    case CanvasItemType.arrow:           return 'arrow';
    case CanvasItemType.diamond:         return 'diamond';
    case CanvasItemType.hexagon:         return 'hexagon';
    case CanvasItemType.skewedRectangle: return 'skewedRectangle';
  }
}

IconData canvasItemTypeIcon(CanvasItemType t) {
  switch (t) {
    case CanvasItemType.textSection:      return LucideIcons.type;
    case CanvasItemType.line:             return LucideIcons.minus;
    case CanvasItemType.rectangle:        return LucideIcons.square;
    case CanvasItemType.circle:           return LucideIcons.circle;
    case CanvasItemType.imageBox:         return LucideIcons.image;
    case CanvasItemType.icon:             return LucideIcons.smile;
    case CanvasItemType.triangle:         return LucideIcons.triangle;
    case CanvasItemType.star:             return LucideIcons.star;
    case CanvasItemType.arrow:            return LucideIcons.arrowRight;
    case CanvasItemType.diamond:          return LucideIcons.diamond;
    case CanvasItemType.hexagon:          return LucideIcons.hexagon;
    case CanvasItemType.skewedRectangle:  return LucideIcons.square;
  }
}

// ─── SHAPE VERTICES ──────────────────────────────────────────────────────

List<Offset> shapeVertices(CanvasItemType type) {
  switch (type) {
    case CanvasItemType.triangle:
      return [const Offset(0.5, 0), const Offset(1, 1), const Offset(0, 1)];
    case CanvasItemType.diamond:
      return [
        const Offset(0.5, 0), const Offset(1, 0.5),
        const Offset(0.5, 1), const Offset(0, 0.5),
      ];
    case CanvasItemType.hexagon:
      return List.generate(6, (i) {
        final angle = (math.pi / 3) * i - math.pi / 6;
        return Offset(0.5 + 0.5 * math.cos(angle), 0.5 + 0.5 * math.sin(angle));
      });
    case CanvasItemType.star:
      final pts = <Offset>[];
      for (int i = 0; i < 10; i++) {
        final angle = (math.pi / 5) * i - math.pi / 2;
        final r = i.isEven ? 0.5 : 0.22;
        pts.add(Offset(0.5 + r * math.cos(angle), 0.5 + r * math.sin(angle)));
      }
      return pts;
    case CanvasItemType.arrow:
      return [
        const Offset(0, 0.3), const Offset(0.6, 0.3), const Offset(0.6, 0),
        const Offset(1, 0.5),
        const Offset(0.6, 1), const Offset(0.6, 0.7), const Offset(0, 0.7),
      ];
    case CanvasItemType.skewedRectangle:
      return [
        const Offset(0.15, 0), const Offset(1, 0),
        const Offset(0.85, 1), const Offset(0, 1),
      ];
    default:
      return [];
  }
}