// Computes the Matrix4 to center + fit ONE page in an editor viewport.
// Shared by CV, Cover Letter, and Proposal editors.
import 'package:flutter/material.dart';
import 'canvas_controller.dart';

class ViewportFitter {
  static Matrix4? fitToPage({
    required Size viewportSize,
    required int page,
    required bool leftOpen,
    required bool rightOpen,
    required bool isMobile,
    double appBar = 56,
    double leftPanelW = 250,
    double rightPanelW = 260,
    double outerPad = 32,
    double controlsH = 64, // page controls bar + 16 spacing
  }) {
    final leftW = (leftOpen && !isMobile) ? leftPanelW : 0.0;
    final rightW = (rightOpen && !isMobile) ? rightPanelW : 0.0;
    final viewW = viewportSize.width - leftW - rightW;
    final viewH = viewportSize.height - appBar;
    if (viewW <= 0 || viewH <= 0) return null;

    const pageW = CanvasController.canvasW;
    const pageH = CanvasController.canvasH;
    const gap = 24.0;

    final scale = (viewH * 0.94 / pageH).clamp(0.3, 2.0);
    final pageTop = outerPad + controlsH + page * (pageH + gap);
    final topMargin = (viewH - pageH * scale) / 2;
    final tx = leftW + (viewW - pageW * scale) / 2 - outerPad * scale;
    final ty = appBar + topMargin - pageTop * scale;

    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }
}