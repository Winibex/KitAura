// lib/shared/canvas/editor_ui/editor_panel_config.dart
//
// Config object that controls which sections appear in editor panels
// (both left "Add Elements" panel and right "Properties" panel).
//
// Each editor (CV / Cover Letter / Proposal) passes a config tailored to
// what its users need.

class EditorPanelConfig {
  // ─── LEFT PANEL (Add Elements) ──────────────────────────────────

  /// Show the Line button.
  final bool showLine;

  /// Show shape buttons (rect, circle, triangle, star, arrow, diamond, hex).
  final bool showShapes;

  /// Show the Image upload button.
  final bool showImage;

  /// Show the Icon picker button.
  final bool showIcon;

  // ─── RIGHT PANEL (Properties) ───────────────────────────────────

  /// Show the Duplicate button on selected items.
  final bool showDuplicate;

  /// Show page size dropdown when nothing is selected.
  final bool showPageSize;

  /// Show canvas background color picker.
  final bool showBackground;

  /// Show AI Compose controls (Generate with AI + Insert Raw Data).
  /// CV: true. Cover Letter: false. Proposal: false.
  final bool showAiCompose;

  /// Show AI Refine controls (5 rewrite modes).
  /// All editors: true.
  final bool showAiRefine;

  /// Show the Career Profile selector dropdown above AI Compose.
  /// Only relevant when showAiCompose is true.
  final bool showCareerProfileSelector;

  const EditorPanelConfig({
    // Left panel defaults
    this.showLine = true,
    this.showShapes = true,
    this.showImage = true,
    this.showIcon = true,
    // Right panel defaults
    this.showDuplicate = true,
    this.showPageSize = true,
    this.showBackground = true,
    this.showAiCompose = true,
    this.showAiRefine = true,
    this.showCareerProfileSelector = true,
  });

  // ─── PRESETS PER EDITOR ─────────────────────────────────────────

  /// CV editor — everything enabled.
  static const EditorPanelConfig cv = EditorPanelConfig();

  /// Cover Letter editor — text-only document.
  /// Shapes/images/icons hidden (letters don't need them).
  /// Right panel: AI Compose hidden (lives in CL details panel with job inputs).
  /// AI Refine kept (users may want to refine individual paragraphs).
  static const EditorPanelConfig coverLetter = EditorPanelConfig(
    showLine: true,
    showShapes: false,
    showImage: false,
    showIcon: false,
    showAiCompose: false,
    showCareerProfileSelector: false,
  );

  /// Proposal editor — full design freedom, but AI Compose lives in the
  /// proposal details panel (with client info). Per-section Compose hidden.
  static const EditorPanelConfig proposal = EditorPanelConfig(
    showAiCompose: false,
    showCareerProfileSelector: false,
  );
}
