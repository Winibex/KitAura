// lib/shared/canvas/snap_guide.dart
//
// Snap-to-align system for the canvas editor.
// When dragging an item, checks alignment with all other items' edges
// and centers. If within threshold, snaps the position and returns
// guide lines to paint on the canvas.
//
// USAGE:
//   final result = SnapGuide.calculate(
//     dragging: draggingItem,
//     allItems: ctrl.items,
//     threshold: 5.0,
//   );
//   // result.snappedPosition → use instead of raw drag position
//   // result.guides → list of lines to paint on the canvas overlay

// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import '../../models/canvas_item.dart';

/// A single alignment guide line to draw on the canvas.
class GuideLine {
  final Offset start;
  final Offset end;
  final bool isHorizontal;

  const GuideLine({
    required this.start,
    required this.end,
    required this.isHorizontal,
  });
}

/// Result of a snap calculation.
class SnapResult {
  /// The snapped position for the dragged item.
  final Offset snappedPosition;

  /// Guide lines to draw on the canvas.
  final List<GuideLine> guides;

  const SnapResult({
    required this.snappedPosition,
    required this.guides,
  });
}

class SnapGuide {
  SnapGuide._();

  /// Default snap threshold in pixels.
  static const double defaultThreshold = 5.0;

  /// Calculate snapped position and guide lines for a dragging item.
  ///
  /// [dragPos] is the current (unsnapped) drag position.
  /// [dragW] and [dragH] are the item's dimensions.
  /// [dragId] is the dragged item's ID (to skip self-comparison).
  /// [allItems] is the full items list.
  /// [canvasW] and [canvasH] are the canvas dimensions.
  static SnapResult calculate({
    required Offset dragPos,
    required double dragW,
    required double dragH,
    required String dragId,
    required List<CanvasItem> allItems,
    required double canvasW,
    required double canvasH,
    double threshold = defaultThreshold,
  }) {
    double snapX = dragPos.dx;
    double snapY = dragPos.dy;
    final guides = <GuideLine>[];

    // Dragged item edges and center
    final dLeft = dragPos.dx;
    final dRight = dragPos.dx + dragW;
    final dCenterX = dragPos.dx + dragW / 2;
    final dTop = dragPos.dy;
    final dBottom = dragPos.dy + dragH;
    final dCenterY = dragPos.dy + dragH / 2;

    double bestDx = threshold + 1; // best horizontal distance found
    double bestDy = threshold + 1; // best vertical distance found

    // Also check canvas center and edges
    final refPoints = <_RefItem>[
      _RefItem(
        left: 0, right: canvasW, top: 0, bottom: canvasH,
        centerX: canvasW / 2, centerY: canvasH / 2,
      ),
    ];

    // Build reference points from all other items
    for (final item in allItems) {
      if (item.id == dragId) continue;
      refPoints.add(_RefItem(
        left: item.position.dx,
        right: item.position.dx + item.width,
        top: item.position.dy,
        bottom: item.position.dy + item.height,
        centerX: item.position.dx + item.width / 2,
        centerY: item.position.dy + item.height / 2,
      ));
    }

    // Track which alignments we snapped to (for drawing guides)
    double? snapToX; // the X coordinate we snapped to
    double? snapToY; // the Y coordinate we snapped to
    String? snapTypeX; // 'left', 'right', 'center'
    String? snapTypeY; // 'top', 'bottom', 'center'

    for (final ref in refPoints) {
      // ── HORIZONTAL SNAPS (X axis) ────────────────────────────────
      // Left edge → left edge
      final llDist = (dLeft - ref.left).abs();
      if (llDist < bestDx) {
        bestDx = llDist;
        snapX = ref.left;
        snapToX = ref.left;
        snapTypeX = 'left';
      }
      // Right edge → right edge
      final rrDist = (dRight - ref.right).abs();
      if (rrDist < bestDx) {
        bestDx = rrDist;
        snapX = ref.right - dragW;
        snapToX = ref.right;
        snapTypeX = 'right';
      }
      // Left edge → right edge
      final lrDist = (dLeft - ref.right).abs();
      if (lrDist < bestDx) {
        bestDx = lrDist;
        snapX = ref.right;
        snapToX = ref.right;
        snapTypeX = 'left';
      }
      // Right edge → left edge
      final rlDist = (dRight - ref.left).abs();
      if (rlDist < bestDx) {
        bestDx = rlDist;
        snapX = ref.left - dragW;
        snapToX = ref.left;
        snapTypeX = 'right';
      }
      // Center → center (X)
      final ccxDist = (dCenterX - ref.centerX).abs();
      if (ccxDist < bestDx) {
        bestDx = ccxDist;
        snapX = ref.centerX - dragW / 2;
        snapToX = ref.centerX;
        snapTypeX = 'center';
      }

      // ── VERTICAL SNAPS (Y axis) ──────────────────────────────────
      // Top → top
      final ttDist = (dTop - ref.top).abs();
      if (ttDist < bestDy) {
        bestDy = ttDist;
        snapY = ref.top;
        snapToY = ref.top;
        snapTypeY = 'top';
      }
      // Bottom → bottom
      final bbDist = (dBottom - ref.bottom).abs();
      if (bbDist < bestDy) {
        bestDy = bbDist;
        snapY = ref.bottom - dragH;
        snapToY = ref.bottom;
        snapTypeY = 'bottom';
      }
      // Top → bottom
      final tbDist = (dTop - ref.bottom).abs();
      if (tbDist < bestDy) {
        bestDy = tbDist;
        snapY = ref.bottom;
        snapToY = ref.bottom;
        snapTypeY = 'top';
      }
      // Bottom → top
      final btDist = (dBottom - ref.top).abs();
      if (btDist < bestDy) {
        bestDy = btDist;
        snapY = ref.top - dragH;
        snapToY = ref.top;
        snapTypeY = 'bottom';
      }
      // Center → center (Y)
      final ccyDist = (dCenterY - ref.centerY).abs();
      if (ccyDist < bestDy) {
        bestDy = ccyDist;
        snapY = ref.centerY - dragH / 2;
        snapToY = ref.centerY;
        snapTypeY = 'center';
      }
    }

    // Only snap if within threshold
    if (bestDx > threshold) snapX = dragPos.dx;
    if (bestDy > threshold) snapY = dragPos.dy;

    // Build guide lines for snapped axes
    if (bestDx <= threshold && snapToX != null) {
      guides.add(GuideLine(
        start: Offset(snapToX, 0),
        end: Offset(snapToX, canvasH),
        isHorizontal: false,
      ));
    }
    if (bestDy <= threshold && snapToY != null) {
      guides.add(GuideLine(
        start: Offset(0, snapToY),
        end: Offset(canvasW, snapToY),
        isHorizontal: true,
      ));
    }

    return SnapResult(
      snappedPosition: Offset(
        snapX.clamp(0, canvasW - dragW),
        snapY.clamp(0, canvasH - dragH),
      ),
      guides: guides,
    );
  }
}

/// Internal: reference edges/center for one item or the canvas.
class _RefItem {
  final double left, right, top, bottom, centerX, centerY;
  const _RefItem({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.centerX,
    required this.centerY,
  });
}

/// Painter that draws snap guide lines on the canvas overlay.
class SnapGuidePainter extends CustomPainter {
  final List<GuideLine> guides;

  SnapGuidePainter(this.guides);

  @override
  void paint(Canvas canvas, Size size) {
    if (guides.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFFFF4081) // magenta/pink guide color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Dashed line
    for (final guide in guides) {
      _drawDashedLine(canvas, guide.start, guide.end, paint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = (dx * dx + dy * dy);
    if (dist == 0) return;
    final len = dist > 0 ? (dx.abs() > dy.abs() ? dx.abs() : dy.abs()) : 0.0;
    final ux = dx / len;
    final uy = dy / len;

    double d = 0;
    while (d < len) {
      final s = Offset(start.dx + ux * d, start.dy + uy * d);
      d += dashLen;
      if (d > len) d = len;
      final e = Offset(start.dx + ux * d, start.dy + uy * d);
      canvas.drawLine(s, e, paint);
      d += gapLen;
    }
  }

  @override
  bool shouldRepaint(SnapGuidePainter old) => guides != old.guides;
}