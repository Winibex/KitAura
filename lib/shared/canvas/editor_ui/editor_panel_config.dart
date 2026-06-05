// lib/shared/canvas/editor_ui/editor_panel_config.dart
//
// Controls which features are visible in EditorLeftPanel and EditorRightPanel.
// Each editor type (CV, Cover Letter, Proposal) uses its own config.

class EditorPanelConfig {
  // Left panel — Add Elements
  final bool showShapes;    // rect, circle, triangle, star, arrow, diamond, hexagon
  final bool showImage;
  final bool showIcon;
  final bool showLine;

  // Right panel — Page Settings
  final bool showPageSize;
  final bool showBackground;

  // Right panel — Item actions
  final bool showDuplicate;

  const EditorPanelConfig({
    this.showShapes = true,
    this.showImage = true,
    this.showIcon = true,
    this.showLine = true,
    this.showPageSize = true,
    this.showBackground = true,
    this.showDuplicate = true,
  });

  /// Full canvas editor — all features enabled.
  static const cv = EditorPanelConfig();

  /// Simplified for cover letters — text, line, AI tools only.
  static const coverLetter = EditorPanelConfig(
    showShapes: false,
    showImage: false,
    showIcon: false,
    showLine: true,
    showPageSize: false,
    showBackground: false,
    showDuplicate: false,
  );

  /// Future: proposals get full canvas like CV.
  static const proposal = EditorPanelConfig();
}