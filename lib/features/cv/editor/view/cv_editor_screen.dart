// lib/features/cv/editor/view/cv_editor_screen.dart
//
// MVC VIEW — UI only. All business logic is in CvEditorController.
// Handles: canvas rendering, panel toggles, marquee, focus wiring,
// keyboard shortcuts, and reacting to controller state.

import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:printing/printing.dart';
import 'package:toastification/toastification.dart';
import 'package:web/web.dart' as web;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../shared/ai/claude_controller.dart';
import '../../../../shared/ai/spellcheck_controller.dart';
import '../../../../shared/canvas/editor_ui/editor_app_bar.dart';
import '../../../../shared/canvas/editor_ui/editor_left_panel.dart';
import '../../../../shared/canvas/editor_ui/editor_right_panel.dart';
import '../../../../shared/canvas/editor_ui/editor_widgets.dart';
import '../../../../shared/canvas/engine/canvas_controller.dart';
import '../../../../shared/canvas/engine/canvas_item_widget.dart';
import '../../../../shared/canvas/engine/shape_painter.dart';
import '../../../../shared/canvas/engine/snap_guide.dart';
import '../../../../shared/models/canvas_item.dart';
import '../../../settings/view/upgrade_modal.dart';
import '../controller/cv_editor_controller.dart';
import 'spellcheck_panel.dart';

class CvEditorScreen extends ConsumerStatefulWidget {
  final String docId;
  const CvEditorScreen({super.key, required this.docId});

  @override
  ConsumerState<CvEditorScreen> createState() => _CvEditorScreenState();
}

class _CvEditorScreenState extends ConsumerState<CvEditorScreen> {
  late final CanvasController _canvas;
  late final CvEditorController _editor;

  // UI-only state
  Offset? _marqueeStart, _marqueeEnd;
  bool _isMarqueeActive = false;
  Key _toolbarKey = UniqueKey();
  bool _leftPanelOpen = true;
  bool _rightPanelOpen = true;
  bool _showSpellcheckPanel = false;
  bool _isEditingTitle = false;
  List<GuideLine> _snapGuides = [];

  final ScrollController _verticalScrollCtrl = ScrollController();
  final _titleCtrl = TextEditingController();
  final Map<String, VoidCallback> _focusListeners = {};

  String? _lastKnownDocId;

  @override
  void initState() {
    super.initState();

    // Create controllers
    _canvas = CanvasController();
    _editor = CvEditorController(canvas: _canvas);

    // Listen to canvas changes → rebuild toolbar + mark dirty
    _canvas.addListener(_onCanvasUpdate);

    // Listen to editor state → handle paywall, errors
    _editor.addListener(_onEditorStateChange);

    // Keyboard shortcuts
    HardwareKeyboard.instance.addHandler(_canvas.handleKeyEvent);

    // Initialize (loads template, auto fills, preloads fonts)
    _editor.initialize(widget.docId).then((_) {
      if (mounted) {
        _titleCtrl.text = _editor.state.title;
        _wireFocusListeners();
        setState(() {});
      }
    });
  }

  void _onCanvasUpdate() {
    if (!mounted) return;
    setState(() => _toolbarKey = UniqueKey());
    _editor.markDirty();
  }

  void _onEditorStateChange() {
    if (!mounted) return;
    final s = _editor.state;

    // Show paywall dialog
    if (s.paywallMessage != null) {
      showDialog(context: context, builder: (_) => const UpgradeModal());
      _editor.clearPaywallMessage();
    }

    // URL update: after first save, replace template ID in URL with real doc ID
    if (s.firestoreDocId != null && s.firestoreDocId != _lastKnownDocId) {
      _lastKnownDocId = s.firestoreDocId;
      // Only replace if current URL has a template ID (not already a Firestore ID)
      if (widget.docId != s.firestoreDocId) {
        GoRouter.of(context).replace('/cv/edit/${s.firestoreDocId}');
      }
    }

    setState(() {});
  }

  void _wireFocusListeners() {
    for (final item in _canvas.items) {
      if (item.isText && item.focusNode != null) {
        if (_focusListeners.containsKey(item.id)) {
          item.focusNode!.removeListener(_focusListeners[item.id]!);
        }
        void listener() {
          if (item.focusNode!.hasFocus && _canvas.selectedId != item.id) {
            _canvas.select(item.id);
            setState(() => _toolbarKey = UniqueKey());
          }
        }
        _focusListeners[item.id] = listener;
        item.focusNode!.addListener(listener);
      }
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_canvas.handleKeyEvent);
    _canvas.removeListener(_onCanvasUpdate);
    _editor.removeListener(_onEditorStateChange);

    // Clean up focus listeners
    for (final entry in _focusListeners.entries) {
      final item = _canvas.items.where((i) => i.id == entry.key).firstOrNull;
      item?.focusNode?.removeListener(entry.value);
    }
    _focusListeners.clear();

    _canvas.disposeAll();
    _canvas.dispose();
    _editor.dispose();
    _verticalScrollCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  // ─── ACTIONS (thin wrappers that call controller) ─────────────────────

  Future<void> _exportPdf() async {
    if (!_canvas.fontsLoaded) return;

    final allowed = await _editor.trackExport();
    if (!allowed) return;

    try {
      final bytes = await _canvas.buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: 'kitaura_cv.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _exportTemplateJson() {
    final json = _canvas.exportTemplateJson();
    final jsonString = const JsonEncoder.withIndent('  ').convert(json);
    final bytes = utf8.encode(jsonString);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = '${widget.docId}.json';
    anchor.click();
    web.URL.revokeObjectURL(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${widget.docId}.json'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _addTextAndWire() {
    final item = _canvas.addTextSection();
    void listener() {
      if (item.focusNode!.hasFocus && _canvas.selectedId != item.id) {
        _canvas.select(item.id);
        setState(() => _toolbarKey = UniqueKey());
      }
    }
    _focusListeners[item.id] = listener;
    item.focusNode!.addListener(listener);
  }

  // ─── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = _editor.state;
    final selected = _canvas.selected;
    final isMulti = _canvas.multiSelected.length > 1;

    // Listen for AI state changes → toasts
    ref.listen<ClaudeState>(claudeControllerProvider, (prev, next) {
      if (next.status == AiFillStatus.error && next.error != null) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('AI Failed'),
          description: Text(next.error!),
          autoCloseDuration: const Duration(seconds: 4),
        );
      }
      if (next.status == AiFillStatus.done) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('AI Complete'),
          description: Text('${next.streamedChars} characters generated'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.lavenderBlush,
      body: Column(
        children: [
          _buildAppBar(s),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: s.isTemplateLoading
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: AppColors.darkRaspberry,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Loading template...',
                                style: TextStyle(
                                  color: AppColors.slateGrey,
                                  fontSize: 13,
                                  fontFamily: AppFonts.poppins,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _buildCanvas(),
                ),
                if (_leftPanelOpen)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: EditorLeftPanel(
                      ctrl: _canvas,
                      onClose: () => setState(() => _leftPanelOpen = false),
                      onAddText: _addTextAndWire,
                    ),
                  ),
                if (_rightPanelOpen)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: _buildRightPanel(selected, isMulti),
                  ),
                if (!_leftPanelOpen)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: EditorPanelToggle(
                      icon: LucideIcons.panelLeft,
                      onTap: () => setState(() => _leftPanelOpen = true),
                    ),
                  ),
                if (!_rightPanelOpen)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: EditorPanelToggle(
                      icon: LucideIcons.panelRight,
                      onTap: () => setState(() => _rightPanelOpen = true),
                    ),
                  ),
                if (_showSpellcheckPanel)
                  Positioned(
                    right: _rightPanelOpen ? 268 : 8,
                    top: 8,
                    child: SpellcheckPanel(
                      items: _canvas.items,
                      onClose: () =>
                          setState(() => _showSpellcheckPanel = false),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── APP BAR ──────────────────────────────────────────────────────────

  Widget _buildAppBar(CvEditorState s) {
    return EditorAppBar(
      title: s.title,
      isEditingTitle: _isEditingTitle,
      titleController: _titleCtrl,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.cvDashboard);
        }
      },
      onTitleTap: () => setState(() {
        _isEditingTitle = true;
        _titleCtrl.text = s.title;
      }),
      onTitleSubmitted: (val) {
        _editor.updateTitle(val);
        setState(() => _isEditingTitle = false);
      },
      canUndo: _canvas.canUndo,
      canRedo: _canvas.canRedo,
      onUndo: _canvas.undo,
      onRedo: _canvas.redo,
      showSavedBadge: s.isSaved && !s.isSaving,
      isSaving: s.isSaving,
      actions: [
        EditorAppBarAction(
          icon: s.isSaving
              ? LucideIcons.loader
              : (s.isSaved ? LucideIcons.cloudCog : LucideIcons.cloud),
          label: s.isSaving ? 'Saving...' : (s.isSaved ? 'Saved' : 'Save'),
          color: s.isSaved ? AppColors.success : AppColors.white,
          bgColor: s.isSaved
              ? AppColors.success.withValues(alpha: 0.2)
              : AppColors.white.withValues(alpha: 0.1),
          onTap: s.isSaving ? null : () => _editor.saveNow(),
        ),
        EditorAppBarAction(
          icon: LucideIcons.fileJson,
          label: 'Save JSON',
          color: AppColors.white,
          bgColor: AppColors.white.withValues(alpha: 0.1),
          onTap: _exportTemplateJson,
        ),
        EditorAppBarAction(
          icon: LucideIcons.download,
          label: 'Export PDF',
          color: AppColors.white,
          bgColor: AppColors.magentaBloom,
          onTap: _canvas.fontsLoaded ? _exportPdf : null,
        ),
      ],
    );
  }

  // ─── RIGHT PANEL ──────────────────────────────────────────────────────

  Widget _buildRightPanel(CanvasItem? selected, bool isMulti) {
    return EditorRightPanel(
      ctrl: _canvas,
      selected: selected,
      isMultiSelected: isMulti,
      toolbarKey: _toolbarKey,
      onClose: () => setState(() => _rightPanelOpen = false),
      onAiFill: (item) async {
        _canvas.saveSnapshot();
        await ref
            .read(claudeControllerProvider.notifier)
            .fillSection(
              itemId: item.id,
              sectionType: item.sectionType,
              sectionTitle: item.title,
              controller: item.controller!,
              cvId: _editor.state.firestoreDocId,
              cvTitle: _editor.state.title,
            );
      },
      isAiFilling:
          ref.watch(claudeControllerProvider).activeOperation == 'fill',
      isSpellchecking: ref.watch(spellcheckControllerProvider).isChecking,
      onSpellcheck: () {
        ref.read(spellcheckControllerProvider.notifier).checkAll(_canvas.items);
        setState(() => _showSpellcheckPanel = true);
      },
      onRewrite: (item, mode, customInstruction) async {
        _canvas.saveSnapshot();
        await ref
            .read(claudeControllerProvider.notifier)
            .rewriteSection(
              itemId: item.id,
              sectionType: item.sectionType,
              sectionTitle: item.title,
              controller: item.controller!,
              mode: mode,
              customInstruction: customInstruction,
              cvId: _editor.state.firestoreDocId,
              cvTitle: _editor.state.title,
            );
      },
    );
  }

  // ─── CANVAS ───────────────────────────────────────────────────────────

  Widget _buildCanvas() {
    return Container(
      color: const Color(0xFFE8E0D8),
      child: Center(
        child: SingleChildScrollView(
          controller: _verticalScrollCtrl,
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  _buildPageControls(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: CanvasController.canvasW,
                    height:
                        _canvas.totalCanvasHeight +
                        ((_canvas.totalPages - 1) * 24),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ...List.generate(
                          _canvas.totalPages,
                          (pageIdx) => _buildPageBackground(pageIdx),
                        ),
                        ..._canvas.items.map(
                          (item) => CanvasItemWidget(
                            key: ValueKey(item.id),
                            item: item,
                            isSelected: item.id == _canvas.selectedId,
                            isMultiSelected: _canvas.multiSelected.contains(
                              item.id,
                            ),
                            canvasW: CanvasController.canvasW,
                            canvasH:
                                _canvas.totalCanvasHeight +
                                ((_canvas.totalPages - 1) * 24),
                            onSelect: () {
                              _canvas.select(item.id);
                              if (item.isText) {
                                setState(() => _toolbarKey = UniqueKey());
                              }
                            },
                            onMultiMoveUpdate:
                                _canvas.multiSelected.contains(item.id)
                                ? (delta) {
                                    _canvas.multiMoveUpdate(delta);
                                    setState(() {});
                                  }
                                : null,
                            onMultiMoveEnd:
                                _canvas.multiSelected.contains(item.id)
                                ? () => _canvas.multiMoveEnd()
                                : null,
                            onSaveSnapshot: _canvas.saveSnapshot,
                            allItems: _canvas.items,
                            onSnapGuidesChanged: (guides) =>
                                setState(() => _snapGuides = guides),
                          ),
                        ),
                        if (_isMarqueeActive &&
                            _marqueeStart != null &&
                            _marqueeEnd != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: MarqueePainter(
                                  _marqueeStart!,
                                  _marqueeEnd!,
                                ),
                              ),
                            ),
                          ),
                        if (_snapGuides.isNotEmpty)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: SnapGuidePainter(_snapGuides),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageBackground(int pageIdx) {
    final yOffset = pageIdx * (CanvasController.canvasH + 24);
    return Positioned(
      left: 0,
      top: yOffset,
      width: CanvasController.canvasW,
      height: CanvasController.canvasH,
      child: GestureDetector(
        onTapDown: (_) => _canvas.deselect(),
        onPanStart: (d) {
          if (_canvas.multiSelected.isNotEmpty) {
            _canvas.startMultiDrag(
              Offset(d.localPosition.dx, d.localPosition.dy + yOffset),
            );
            return;
          }
          setState(() {
            _isMarqueeActive = true;
            _marqueeStart = Offset(
              d.localPosition.dx,
              d.localPosition.dy + yOffset,
            );
            _marqueeEnd = _marqueeStart;
          });
        },
        onPanUpdate: (d) {
          if (_canvas.isMultiDragging) {
            _canvas.updateMultiDrag(
              Offset(d.localPosition.dx, d.localPosition.dy + yOffset),
            );
            setState(() {});
            return;
          }
          if (_isMarqueeActive) {
            setState(
              () => _marqueeEnd = Offset(
                d.localPosition.dx,
                d.localPosition.dy + yOffset,
              ),
            );
          }
        },
        onPanEnd: (_) {
          if (_canvas.isMultiDragging) {
            _canvas.endMultiDrag();
            return;
          }
          if (_isMarqueeActive) _onMarqueeEnd();
        },
        child: Container(
          decoration: BoxDecoration(
            color: _canvas.canvasBackground,
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                bottom: 8,
                right: 12,
                child: Text(
                  'Page ${pageIdx + 1}',
                  style: TextStyle(
                    color: AppColors.slateGrey.withValues(alpha: 0.3),
                    fontSize: 10,
                    fontFamily: AppFonts.poppins,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(_canvas.totalPages, (i) {
            final isActive = _canvas.currentPage == i;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _canvas.goToPage(i);
                    _verticalScrollCtrl.animateTo(
                      i * (CanvasController.canvasH + 24) + 32,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.darkRaspberry
                          : AppColors.lavenderBlush,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          color: isActive
                              ? AppColors.white
                              : AppColors.prussianBlue,
                          fontSize: 12,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                _canvas.saveSnapshot();
                _canvas.addPage();
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.lavenderBlush,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.petalFrost),
                ),
                child: const Icon(
                  LucideIcons.plus,
                  size: 14,
                  color: AppColors.darkRaspberry,
                ),
              ),
            ),
          ),
          if (_canvas.totalPages > 1) ...[
            const SizedBox(width: 4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _showRemovePageDialog(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: AppColors.error,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Text(
            '${_canvas.totalPages} ${_canvas.totalPages == 1 ? 'page' : 'pages'}',
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 11,
              fontFamily: AppFonts.poppins,
            ),
          ),
        ],
      ),
    );
  }

  void _showRemovePageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove Page?',
          style: TextStyle(
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
            color: AppColors.prussianBlue,
          ),
        ),
        content: Text(
          'Delete page ${_canvas.currentPage + 1} and all its contents?',
          style: const TextStyle(
            fontFamily: AppFonts.openSans,
            color: AppColors.slateGrey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.slateGrey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _canvas.saveSnapshot();
              _canvas.removePage(_canvas.currentPage);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _onMarqueeEnd() {
    if (_marqueeStart == null || _marqueeEnd == null) {
      setState(() {
        _isMarqueeActive = false;
        _marqueeStart = null;
        _marqueeEnd = null;
      });
      return;
    }
    _canvas.marqueeSelect(Rect.fromPoints(_marqueeStart!, _marqueeEnd!));
    setState(() {
      _isMarqueeActive = false;
      _marqueeStart = null;
      _marqueeEnd = null;
      if (_canvas.multiSelected.length == 1) _toolbarKey = UniqueKey();
    });
  }
}