// lib/features/cv/view/cv_editor_screen.dart

import 'dart:convert';
import 'dart:js_interop';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kitaura/core/constants/app_routes.dart';
import 'package:kitaura/features/cv/view/spellcheck_panel.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:printing/printing.dart';
import 'package:toastification/toastification.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../shared/canvas/editor_app_bar.dart';
import '../../../shared/canvas/editor_left_panel.dart';
import '../../../shared/canvas/editor_right_panel.dart';
import '../../../shared/canvas/editor_widgets.dart';
import '../../../shared/services/firebase_service.dart';
import '../../../shared/canvas/canvas_controller.dart';
import '../../cv_templates/data/cv_template_data.dart';
import '../controller/claude_controller.dart';
import '../../../shared/models/canvas_item.dart';

import '../../../shared/canvas/canvas_item_widget.dart';
import '../../../shared/canvas/shape_painter.dart';
import 'package:web/web.dart' as web;

import '../controller/spellcheck_controller.dart';

// ──────────────────────────────────────────────────────────────────────────
// CHANGED: StatefulWidget → ConsumerStatefulWidget for Riverpod access
// ──────────────────────────────────────────────────────────────────────────

class CvEditorScreen extends ConsumerStatefulWidget {
  final String docId;
  const CvEditorScreen({super.key, required this.docId});

  @override
  ConsumerState<CvEditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<CvEditorScreen> {
  final CanvasController _ctrl = CanvasController();

  Offset? _marqueeStart, _marqueeEnd;
  bool _isMarqueeActive = false;
  Key _toolbarKey = UniqueKey();
  bool _leftPanelOpen = true;
  bool _rightPanelOpen = true;

  final ScrollController _verticalScrollCtrl = ScrollController();

  String _cvTitle = 'Untitled CV';
  String? _firestoreDocId; // actual Firestore doc ID for saving
  bool _isEditingTitle = false;
  final _titleCtrl = TextEditingController();

  bool _showSpellcheckPanel = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onControllerUpdate);

    // Resolve title: check CvTemplateData registry first, then fallback
    final info = CvTemplateData.getInfo(widget.docId);
    if (widget.docId == 'blank') {
      _cvTitle = 'Untitled CV';
    } else if (info != null) {
      _cvTitle = '${info.label} CV';
    } else {
      // It's a Firestore document ID
      _cvTitle = 'Untitled CV';
      _firestoreDocId = widget.docId;
    }
    _titleCtrl.text = _cvTitle;

    _loadInitialTemplate();
    HardwareKeyboard.instance.addHandler(_ctrl.handleKeyEvent);
  }

  void _loadInitialTemplate() async {
    if (widget.docId == 'blank') {
      _ctrl.init();
    } else if (CvTemplateData.isTemplateId(widget.docId)) {
      // Load from JSON asset via CvTemplateData
      final json = await CvTemplateData.loadTemplateJson(widget.docId);
      _ctrl.applyTemplateJson(json);
    } else {
      // It's a Firestore document ID — load saved CV
      await _loadFromFirestore(widget.docId);
    }

    // Wire focus listeners for all text items loaded
    _wireFocusListeners();

    await _ctrl.preloadFonts();
    if (mounted) setState(() {});
  }

  /// Wire focus listeners on all text items so tapping a text section
  /// auto-selects it in the canvas controller.
  void _wireFocusListeners() {
    for (final item in _ctrl.items) {
      if (item.isText && item.focusNode != null) {
        item.focusNode!.addListener(() {
          if (item.focusNode!.hasFocus && _ctrl.selectedId != item.id) {
            _ctrl.select(item.id);
            setState(() => _toolbarKey = UniqueKey());
          }
        });
      }
    }
  }

  Future<void> _loadFromFirestore(String docId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _ctrl.init();
      return;
    }

    try {
      final doc = await FirebaseService.getCV(uid, docId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        // Update title
        setState(() {
          _cvTitle = data['title'] as String? ?? 'Untitled CV';
        });

        // Load canvas from saved JSON — same format as template JSON
        final canvasData = <String, dynamic>{
          'canvasBackground': data['canvasBackground'] ?? '#FFFFFF',
          'items': data['items'] ?? [],
        };

        await _ctrl.loadFromJson(canvasData);
      } else {
        _ctrl.init();
      }
    } catch (e) {
      debugPrint('Load from Firestore failed: $e');
      _ctrl.init();
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() => _toolbarKey = UniqueKey());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_ctrl.handleKeyEvent);
    _ctrl.removeListener(_onControllerUpdate);
    _ctrl.disposeAll();
    _verticalScrollCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportPdf() async {
    if (!_ctrl.fontsLoaded) return;
    try {
      final bytes = await _ctrl.buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: 'kitaura_cv.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF error: $e')));
      }
    }
  }

  void _exportTemplateJson() {
    final json = _ctrl.exportTemplateJson();
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

  Future<void> _saveToCloud() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final data = _ctrl.toFirestoreJson(uid, _cvTitle);
      // Add title explicitly
      data['title'] = _cvTitle;

      if (_firestoreDocId != null) {
        // Update existing CV
        await FirebaseService.updateCV(uid, _firestoreDocId!, data);
      } else {
        // Create new CV
        final docRef = await FirebaseService.createCV(uid, data);
        _firestoreDocId = docRef.id;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CV saved!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selected = _ctrl.selected;
    final isMulti = _ctrl.multiSelected.length > 1;

    // ── NEW: Listen for AI Fill state changes → show toasts ──────────
    ref.listen<ClaudeState>(claudeControllerProvider, (prev, next) {
      if (next.status == AiFillStatus.error && next.error != null) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          title: const Text('AI Fill Failed'),
          description: Text(next.error!),
          autoCloseDuration: const Duration(seconds: 4),
        );
      }
      if (next.status == AiFillStatus.done) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          title: const Text('AI Fill Complete'),
          description: Text('${next.streamedChars} characters generated'),
          autoCloseDuration: const Duration(seconds: 2),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.lavenderBlush,
      body: Column(
        children: [
          EditorAppBar(
            title: _cvTitle,
            isEditingTitle: _isEditingTitle,
            titleController: _titleCtrl,
            onBack: (){
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.cvTemplates);
                }
              },
            onTitleTap: () => setState(() {
              _isEditingTitle = true;
              _titleCtrl.text = _cvTitle;
            }),
            onTitleSubmitted: (val) => setState(() {
              _cvTitle = val.trim().isEmpty ? 'Untitled CV' : val.trim();
              _isEditingTitle = false;
            }),
            canUndo: _ctrl.canUndo,
            canRedo: _ctrl.canRedo,
            onUndo: _ctrl.undo,
            onRedo: _ctrl.redo,
            showSavedBadge: true,
            actions: [
              EditorAppBarAction(
                icon: LucideIcons.cloud,
                label: 'Save',
                color: AppColors.success,
                bgColor: AppColors.success.withValues(alpha: 0.2),
                onTap: _saveToCloud,
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
                onTap: _ctrl.fontsLoaded ? _exportPdf : null,
              ),
            ],
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Canvas always centered, full width
                Positioned.fill(child: _buildCanvas()),
                // Left panel overlay
                if (_leftPanelOpen)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: EditorLeftPanel(
                      ctrl: _ctrl,
                      onClose: () => setState(() => _leftPanelOpen = false),
                      onAddText: _addTextAndWire,
                    ),
                  ),
                // Right panel overlay
                if (_rightPanelOpen)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: EditorRightPanel(
                      ctrl: _ctrl,
                      selected: selected,
                      isMultiSelected: isMulti,
                      toolbarKey: _toolbarKey,
                      onClose: () => setState(() => _rightPanelOpen = false),
                      extraContentBuilder: (item) => _buildAiFillButton(item),
                      // NEW: spellcheck
                      isSpellchecking: ref.watch(spellcheckControllerProvider).isChecking,
                      onSpellcheck: () {
                        ref.read(spellcheckControllerProvider.notifier).checkAll(_ctrl.items);
                        setState(() => _showSpellcheckPanel = true);
                      },
                    ),
                  ),
                // Panel toggle buttons when panels are closed
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
                // Spellcheck results panel
                if (_showSpellcheckPanel)
                  Positioned(
                    right: _rightPanelOpen ? 268 : 8,
                    top: 8,
                    child: SpellcheckPanel(
                      items: _ctrl.items,
                      onClose: () => setState(() => _showSpellcheckPanel = false),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addTextAndWire() {
    final item = _ctrl.addTextSection();
    item.focusNode!.addListener(() {
      if (item.focusNode!.hasFocus && _ctrl.selectedId != item.id) {
        _ctrl.select(item.id);
        setState(() => _toolbarKey = UniqueKey());
      }
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // AI FILL BUTTON + PAYWALL + STREAMING INDICATOR
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildAiFillButton(CanvasItem item) {
    final claudeState = ref.watch(claudeControllerProvider);
    final isThisItem = claudeState.activeItemId == item.id;
    final isActive = claudeState.isActive && isThisItem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorSectionLabel('AI CONTENT'),
        const SizedBox(height: 6),

        // Main button — toggles between Fill and Cancel
        SizedBox(
          width: double.infinity,
          height: 36,
          child: ElevatedButton.icon(
            onPressed: isActive
                ? () => ref.read(claudeControllerProvider.notifier).cancel()
                : () => ref
                .read(claudeControllerProvider.notifier)
                .fillSection(
              itemId: item.id,
              sectionTitle: item.title,
              controller: item.controller!,
              cvId: widget.docId,
            ),
            icon: isActive
                ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.white,
              ),
            )
                : const Icon(LucideIcons.sparkles, size: 14),
            label: Text(
              isActive ? 'Cancel' : 'AI Fill — ${item.title}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive
                  ? AppColors.slateGrey
                  : AppColors.magentaBloom,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),

        // Streaming character count
        if (isActive && claudeState.streamedChars > 0) ...[
          const SizedBox(height: 4),
          Text(
            '${claudeState.streamedChars} characters generated...',
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 10,
              fontFamily: AppFonts.openSans,
            ),
          ),
        ],

        // Error display
        if (claudeState.status == AiFillStatus.error && isThisItem) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              claudeState.error ?? 'Something went wrong.',
              style: const TextStyle(color: AppColors.error, fontSize: 11),
            ),
          ),
        ],

        // Paywall display
        if (claudeState.status == AiFillStatus.paywalled && isThisItem) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.petalFrost,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.almondSilk),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      LucideIcons.sparkles,
                      size: 14,
                      color: AppColors.darkRaspberry,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Free AI fills used up',
                      style: TextStyle(
                        color: AppColors.prussianBlue,
                        fontSize: 12,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Upgrade to Pro for unlimited AI generation.',
                  style: TextStyle(
                    color: AppColors.slateGrey,
                    fontSize: 11,
                    fontFamily: AppFonts.openSans,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: Show upgrade modal
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkRaspberry,
                      foregroundColor: AppColors.white,
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w500,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('Upgrade to Pro'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
                  // Page indicator + add page
                  _buildPageControls(),
                  const SizedBox(height: 16),
                  // All pages stacked
                  SizedBox(
                    width: CanvasController.canvasW,
                    height:
                    _ctrl.totalCanvasHeight + ((_ctrl.totalPages - 1) * 24),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Page backgrounds
                        ...List.generate(_ctrl.totalPages, (pageIdx) {
                          final yOffset =
                              pageIdx * (CanvasController.canvasH + 24);
                          return Positioned(
                            left: 0,
                            top: yOffset,
                            width: CanvasController.canvasW,
                            height: CanvasController.canvasH,
                            child: GestureDetector(
                              onTapDown: (_) => _ctrl.deselect(),
                              onPanStart: (d) => setState(() {
                                _isMarqueeActive = true;
                                _marqueeStart = Offset(
                                  d.localPosition.dx,
                                  d.localPosition.dy + yOffset,
                                );
                                _marqueeEnd = _marqueeStart;
                              }),
                              onPanUpdate: (d) {
                                if (_isMarqueeActive) {
                                  setState(() {
                                    _marqueeEnd = Offset(
                                      d.localPosition.dx,
                                      d.localPosition.dy + yOffset,
                                    );
                                  });
                                }
                              },
                              onPanEnd: (_) {
                                if (_isMarqueeActive) _onMarqueeEnd();
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _ctrl.canvasBackground,
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
                                    // Page number watermark
                                    Positioned(
                                      bottom: 8,
                                      right: 12,
                                      child: Text(
                                        'Page ${pageIdx + 1}',
                                        style: TextStyle(
                                          color: AppColors.slateGrey.withValues(
                                            alpha: 0.3,
                                          ),
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
                        }),

                        // Canvas items
                        ..._ctrl.items.map(
                              (item) => CanvasItemWidget(
                            key: ValueKey(item.id),
                            item: item,
                            isSelected: item.id == _ctrl.selectedId,
                            isMultiSelected: _ctrl.multiSelected.contains(
                              item.id,
                            ),
                            canvasW: CanvasController.canvasW,
                            canvasH:
                            _ctrl.totalCanvasHeight +
                                ((_ctrl.totalPages - 1) * 24),
                            onSelect: () {
                              _ctrl.select(item.id);
                              if (item.isText) {
                                setState(() => _toolbarKey = UniqueKey());
                              }
                            },
                            onMultiMoveUpdate:
                            _ctrl.multiSelected.contains(item.id)
                                ? _ctrl.multiMoveUpdate
                                : null,
                            onSaveSnapshot: _ctrl.saveSnapshot,
                          ),
                        ),

                        // Marquee overlay
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
          // Page navigation
          ...List.generate(_ctrl.totalPages, (i) {
            final isActive = _ctrl.currentPage == i;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _ctrl.goToPage(i);
                    final targetY = i * (CanvasController.canvasH + 24) + 32;
                    _verticalScrollCtrl.animateTo(
                      targetY,
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
          // Add page button
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                _ctrl.saveSnapshot();
                _ctrl.addPage();
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
          // Remove page (only if more than 1)
          if (_ctrl.totalPages > 1) ...[
            const SizedBox(width: 4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: const Text(
                        'Remove Page?',
                        style: TextStyle(
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.bold,
                          color: AppColors.prussianBlue,
                        ),
                      ),
                      content: Text(
                        'Delete page ${_ctrl.currentPage + 1} and all its contents?',
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
                            _ctrl.saveSnapshot();
                            _ctrl.removePage(_ctrl.currentPage);
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
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
            '${_ctrl.totalPages} ${_ctrl.totalPages == 1 ? 'page' : 'pages'}',
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

  void _onMarqueeEnd() {
    if (_marqueeStart == null || _marqueeEnd == null) {
      setState(() {
        _isMarqueeActive = false;
        _marqueeStart = null;
        _marqueeEnd = null;
      });
      return;
    }
    _ctrl.marqueeSelect(Rect.fromPoints(_marqueeStart!, _marqueeEnd!));
    setState(() {
      _isMarqueeActive = false;
      _marqueeStart = null;
      _marqueeEnd = null;
      if (_ctrl.multiSelected.length == 1) _toolbarKey = UniqueKey();
    });
  }
}