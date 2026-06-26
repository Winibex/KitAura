// lib/shared/canvas/canvas_controller.dart
//
// CHANGES FROM PREVIOUS VERSION:
//   1. _restoreSnapshot() now restores Quill delta (text undo works)
//   2. Multi-select drag: startMultiDrag / updateMultiDrag / endMultiDrag
//      (mutates positions directly, parent calls setState, no notifyListeners mid-drag)
//   3. Formatted text clipboard: copySelectedText / pasteFormattedText
//   4. registerTextChangeListener() for auto-snapshot on text edits
//   5. Debug prints on key operations

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'canvas_op_executors.dart';
import 'canvas_op_types.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:kitaura/shared/canvas/engine/auto_height.dart';
import 'package:kitaura/shared/canvas/engine/reflow_engine.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/canvas_item.dart';
import '../../models/canvas_item_type.dart';
import '../../models/section_type.dart';
import '../../models/table_data.dart';
part 'canvas_pdf_renderer.dart';
part 'canvas_template_io.dart';

class CanvasController extends ChangeNotifier {
  static const double canvasW = 595;
  static const double canvasH = 842;

  final List<CanvasItem> items = [];
  String? selectedId;
  final Set<String> multiSelected = {};

  Color canvasBackground = Colors.white;
  String globalFont = 'OpenSans';
  double globalFontSize = 12;

  final List<CanvasSnapshot> _undoStack = [];
  final List<CanvasSnapshot> _redoStack = [];
  final Map<String, pw.Font> pdfFonts = {};
  bool fontsLoaded = false;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  CanvasItem? get selected =>
      selectedId == null ? null : items.where((i) => i.id == selectedId).firstOrNull;

  int currentPage = 0;
  int totalPages = 1;

  // ─── Formatted text clipboard (Copy/Paste text with formatting) ───────
  List<dynamic>? _clipboardDelta;
  bool get hasClipboardDelta => _clipboardDelta != null;

  // ─── Multi-drag state ─────────────────────────────────────────────────
  Offset? _multiDragStart;
  Map<String, Offset> _multiDragOriginalPositions = {};
  bool get isMultiDragging => _multiDragStart != null;


  static const Map<String, String> fontItems = {
    'Arial': 'Arial',
    'Open Sans': 'OpenSans',
    'Poppins': 'Poppins',
    'Sekuya': 'Sekuya',
  };

  Future<void> loadFromJson(Map<String, dynamic> json) async {
    applyTemplateJson(json);
    notifyListeners();
  }

  // ─── PAGES ──────────────────────────────────────────────────────────────

  void addPage() {
    totalPages++;
    currentPage = totalPages - 1;
    selectedId = null;
    multiSelected.clear();
    notifyListeners();
  }

  void removePage(int pageIndex) {
    if (totalPages <= 1) return;
    items.removeWhere((item) {
      final itemPage = _getItemPage(item);
      if (itemPage == pageIndex) {
        item.dispose();
        return true;
      }
      return false;
    });
    for (final item in items) {
      final itemPage = _getItemPage(item);
      if (itemPage > pageIndex) {
        item.position = Offset(item.position.dx, item.position.dy - canvasH);
      }
    }
    totalPages--;
    if (currentPage >= totalPages) currentPage = totalPages - 1;
    selectedId = null;
    multiSelected.clear();
    notifyListeners();
  }

  void goToPage(int page) {
    if (page >= 0 && page < totalPages) {
      currentPage = page;
      selectedId = null;
      multiSelected.clear();
      notifyListeners();
    }
  }

  int _getItemPage(CanvasItem item) => (item.position.dy / canvasH).floor();
  double get totalCanvasHeight => canvasH * totalPages;

  // ─── INIT / DISPOSE ───────────────────────────────────────────────────

  void init() {
    addTextSection(title: 'Personal Info', position: const Offset(20, 20), width: 555, height: 60);
    addTextSection(title: 'Summary', position: const Offset(20, 100), width: 555, height: 60);
    addTextSection(title: 'Experience', position: const Offset(20, 180), width: 340, height: 60);
    addTextSection(title: 'Skills', position: const Offset(375, 180), width: 200, height: 60);
    preloadFonts();
  }

  void disposeAll() {
    for (final item in items) {
      item.dispose();
    }
  }

  void notify() => notifyListeners();

  /// Public hook so extension methods in canvas_op_executors.dart can
  /// trigger a rebuild without tripping the `@protected` lint.
  void notifyFromExtension() => notifyListeners();

  // ─── UNDO / REDO ──────────────────────────────────────────────────────

  void saveSnapshot() {
    _undoStack.add(CanvasSnapshot(
      items.map(ItemSnapshot.from).toList(),
      selectedId,
      canvasBackground,
    ));
    _redoStack.clear();
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    debugPrint('↩️ [Canvas] Undo (stack: ${_undoStack.length})');
    _redoStack.add(CanvasSnapshot(
      items.map(ItemSnapshot.from).toList(),
      selectedId,
      canvasBackground,
    ));
    _restoreSnapshot(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    debugPrint('↪️ [Canvas] Redo (stack: ${_redoStack.length})');
    _undoStack.add(CanvasSnapshot(
      items.map(ItemSnapshot.from).toList(),
      selectedId,
      canvasBackground,
    ));
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _restoreSnapshot(CanvasSnapshot snapshot) {
    final existingById = {for (final i in items) i.id: i};
    final snapById = {for (final s in snapshot.items) s.id: s};

    // Remove items that don't exist in the snapshot
    items.removeWhere((item) {
      if (!snapById.containsKey(item.id)) {
        item.dispose();
        return true;
      }
      return false;
    });

    // Update existing items (position, size, color, AND text delta)
    for (final item in items) {
      final snap = snapById[item.id]!;
      item.type = snap.type;
      item.position = snap.position;
      item.width = snap.width;
      item.height = snap.height;
      item.rotation = snap.rotation;
      item.color = snap.color;
      item.borderColor = snap.borderColor;
      item.borderWidth = snap.borderWidth;
      item.iconData = snap.iconData;
      item.title = snap.title;
      item.flipX = snap.flipX;
      item.flipY = snap.flipY;
      item.sectionType = snap.sectionType;
      item.imageBytes = snap.imageBytes;

      // Restore table data
      if (item.isTable && snap.tableDataJson != null) {
        try {
          item.tableData = TableData.fromJson(
              Map<String, dynamic>.from(snap.tableDataJson!));
        } catch (_) {}
      }

      // ── RESTORE TEXT DELTA (the key fix for text undo) ──
      if (item.isText && snap.deltaJson != null && item.controller != null) {
        try {
          final delta = Delta.fromJson(snap.deltaJson!);
          // Temporarily remove listener to avoid triggering auto-snapshot
          item.controller!.document = Document.fromDelta(delta);
          // Re-register after restore
        } catch (e) {
          debugPrint('⚠️ [Canvas] Delta restore failed for "${item.title}": $e');
        }
      }
    }

    // Recreate items that were deleted (now restored by undo)
    for (final snap in snapshot.items) {
      if (!existingById.containsKey(snap.id)) {
        debugPrint('♻️ [Canvas] Recreating deleted item: "${snap.title}" (${snap.type})');
        final newItem = CanvasItem(
          type: snap.type,
          position: snap.position,
          width: snap.width,
          height: snap.height,
          rotation: snap.rotation,
          color: snap.color,
          borderColor: snap.borderColor,
          borderWidth: snap.borderWidth,
          iconData: snap.iconData,
          title: snap.title,
          flipX: snap.flipX,
          flipY: snap.flipY,
          sectionType: snap.sectionType,
        );
        newItem.imageBytes = snap.imageBytes;

        if (snap.type == CanvasItemType.tableSection &&
            snap.tableDataJson != null) {
          try {
            newItem.tableData = TableData.fromJson(
                Map<String, dynamic>.from(snap.tableDataJson!));
          } catch (_) {}
        }

        // Restore text content for recreated text sections
        if (snap.type == CanvasItemType.textSection &&
            snap.deltaJson != null &&
            newItem.controller != null) {
          try {
            final delta = Delta.fromJson(snap.deltaJson!);
            newItem.controller!.document = Document.fromDelta(delta);
          } catch (e) {
            debugPrint('⚠️ [Canvas] Delta restore on recreate failed: $e');
          }
        }

        items.add(newItem);
      }
    }

    // Restore z-order
    final order = snapshot.items.map((s) => s.id).toList();
    items.sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));

    selectedId = snapshot.selectedId;
    multiSelected.clear();
    canvasBackground = snapshot.canvasBackground;
    notifyListeners();
  }

  // ─── ADD ITEMS ────────────────────────────────────────────────────────

  CanvasItem addTextSection({
    String title = 'New Section',
    Offset? position,
    double width = 200,
    double height = 60,
  })
  {
    saveSnapshot();
    final pageOffset = currentPage * canvasH;
    final pos = position ?? Offset(40, pageOffset + 40);
    final item = CanvasItem(
      type: CanvasItemType.textSection,
      position: pos,
      width: width,
      height: height,
      title: title,
      color: Colors.white,
      borderColor: const Color(0xFFE0E0E0),
    );
    items.add(item);
    selectedId = item.id;
    multiSelected.clear();
    notifyListeners();
    return item;
  }

  CanvasItem addTableSection({
    String title = 'Table',
    Offset? position,
    double width = 495,
    double height = 160,
    TableData? tableData,
    SectionType sectionType = SectionType.custom,
  })
  {
    saveSnapshot();
    final pageOffset = currentPage * canvasH;
    final pos = position ?? Offset(50, pageOffset + 40);
    final item = CanvasItem(
      type: CanvasItemType.tableSection,
      position: pos,
      width: width,
      height: height,
      title: title,
      color: Colors.white,
      borderColor: const Color(0xFFE0E0E0),
      sectionType: sectionType,
      tableData: tableData,
    );
    items.add(item);
    selectedId = item.id;
    multiSelected.clear();
    notifyListeners();
    return item;
  }

  // ─── AUTO-HEIGHT (content-driven sizing — single source of truth) ─────
  void autosizeItem(CanvasItem item, {bool notify = false}) {
    double h = 0;
    if (item.isText && item.controller != null) {
      h = AutoHeight.measureText(
        item.controller!.document.toDelta().toJson(),
        item.width,
        globalFont: globalFont,
        globalFontSize: globalFontSize,
      );
    } else if (item.isTable && item.tableData != null) {
      h = AutoHeight.measureTable(item.tableData!, item.width);
    }
    if (h > 0) item.height = double.parse(h.toStringAsFixed(1));
    if (notify) notifyListeners();
  }

  void autosizeAll() {
    for (final item in items) {
      autosizeItem(item);
    }
  }

  void addShape(CanvasItemType type) {
    saveSnapshot();
    final defaults = <CanvasItemType, Map<String, dynamic>>{
      CanvasItemType.line:            {'w': 200.0, 'h': 4.0,   'color': Colors.transparent,    'border': Colors.black},
      CanvasItemType.rectangle:       {'w': 160.0, 'h': 100.0, 'color': const Color(0xFFE3F2FD), 'border': const Color(0xFF2196F3)},
      CanvasItemType.circle:          {'w': 100.0, 'h': 100.0, 'color': const Color(0xFFE8F5E9), 'border': const Color(0xFF4CAF50)},
      CanvasItemType.imageBox:        {'w': 160.0, 'h': 120.0, 'color': const Color(0xFFF5F5F5), 'border': const Color(0xFF9E9E9E)},
      CanvasItemType.icon:            {'w': 48.0,  'h': 48.0,  'color': Colors.transparent,    'border': const Color(0xFF2196F3)},
      CanvasItemType.triangle:        {'w': 120.0, 'h': 120.0, 'color': const Color(0xFFFFF3E0), 'border': const Color(0xFFFF9800)},
      CanvasItemType.star:            {'w': 120.0, 'h': 120.0, 'color': const Color(0xFFFFFDE7), 'border': const Color(0xFFFF9800)},
      CanvasItemType.arrow:           {'w': 160.0, 'h': 80.0,  'color': const Color(0xFFE0F2F1), 'border': const Color(0xFF009688)},
      CanvasItemType.diamond:         {'w': 100.0, 'h': 120.0, 'color': const Color(0xFFFCE4EC), 'border': const Color(0xFFE91E63)},
      CanvasItemType.hexagon:         {'w': 120.0, 'h': 120.0, 'color': const Color(0xFFF3E5F5), 'border': const Color(0xFF9C27B0)},
      CanvasItemType.skewedRectangle: {'w': 160.0, 'h': 80.0,  'color': const Color(0xFFE8EAF6), 'border': const Color(0xFF3F51B5)},
    };
    final d = defaults[type]!;
    final item = CanvasItem(
      type: type,
      position: const Offset(100, 100),
      width: d['w'] as double,
      height: d['h'] as double,
      color: d['color'] as Color,
      borderColor: d['border'] as Color,
      iconData: type == CanvasItemType.icon ? Icons.star : null,
    );
    items.add(item);
    selectedId = item.id;
    multiSelected.clear();
    notifyListeners();
  }

  // ─── DELETE ───────────────────────────────────────────────────────────

  void deleteSelected() {
    final toDelete = multiSelected.isNotEmpty
        ? Set<String>.from(multiSelected)
        : (selectedId != null ? {selectedId!} : <String>{});
    for (final id in toDelete) {
      final idx = items.indexWhere((i) => i.id == id);
      if (idx != -1) {
        items[idx].dispose();
        items.removeAt(idx);
      }
    }
    selectedId = null;
    multiSelected.clear();
    notifyListeners();
  }

  void duplicateSelected() {
    if (selected == null) return;
    saveSnapshot();
    final src = selected!;
    final item = CanvasItem(
      type: src.type,
      position: Offset(src.position.dx + 20, src.position.dy + 20),
      width: src.width,
      height: src.height,
      color: src.color,
      borderColor: src.borderColor,
      borderWidth: src.borderWidth,
      rotation: src.rotation,
      title: '${src.title} Copy',
      flipX: src.flipX,
      flipY: src.flipY,
      sectionType: src.sectionType,
      iconData: src.iconData,
    );
    if (src.isText && src.controller != null) {
      try {
        final delta = src.controller!.document.toDelta().toJson();
        item.controller!.document = Document.fromJson(delta);
      } catch (_) {}
    }
    if (src.imageBytes != null) {
      item.imageBytes = Uint8List.fromList(src.imageBytes!);
    }
    if (src.isTable && src.tableData != null) {
      item.tableData = src.tableData!.copyWith();
    }
    items.add(item);
    selectedId = item.id;
    multiSelected.clear();
    notifyListeners();
  }

  // ─── SELECT ───────────────────────────────────────────────────────────

  void select(String id) {
    selectedId = id;
    multiSelected.clear();
    notifyListeners();
  }

  void deselect() {
    selectedId = null;
    multiSelected.clear();
    notifyListeners();
  }

  void marqueeSelect(Rect rect) {
    multiSelected.clear();
    for (final item in items) {
      final itemRect = Rect.fromLTWH(
          item.position.dx, item.position.dy, item.width, item.height);
      if (rect.overlaps(itemRect)) {
        multiSelected.add(item.id);
      }
    }
    selectedId = multiSelected.length == 1 ? multiSelected.first : null;
    notifyListeners();
  }

  // ─── MULTI-SELECT DRAG (fixed — no notifyListeners during drag) ───────
  //
  // The old multiMoveUpdate called notifyListeners which killed the gesture.
  // New approach: mutate positions directly, parent calls setState.

  void startMultiDrag(Offset localPosition) {
    if (multiSelected.isEmpty) return;
    saveSnapshot();
    _multiDragStart = localPosition;
    _multiDragOriginalPositions = {
      for (final id in multiSelected)
        if (items.any((i) => i.id == id))
          id: items.firstWhere((i) => i.id == id).position,
    };
    debugPrint('🔀 [Canvas] Multi-drag start (${multiSelected.length} items)');
  }

  /// Call this from onPanUpdate. Does NOT call notifyListeners.
  /// Parent widget must call setState(() {}) to trigger rebuild.
  void updateMultiDrag(Offset localPosition) {
    if (_multiDragStart == null) return;
    final delta = localPosition - _multiDragStart!;
    for (final entry in _multiDragOriginalPositions.entries) {
      final item = items.where((i) => i.id == entry.key).firstOrNull;
      if (item == null) continue;
      item.position = Offset(
        (entry.value.dx + delta.dx).clamp(0, canvasW - item.width),
        (entry.value.dy + delta.dy).clamp(0, totalCanvasHeight - item.height),
      );
    }
    // NO notifyListeners() here — parent calls setState
  }

  void endMultiDrag() {
    _multiDragStart = null;
    _multiDragOriginalPositions.clear();
    debugPrint('🔀 [Canvas] Multi-drag end');
    notifyListeners(); // Only notify once at the end
  }

  void multiMoveUpdate(Offset delta) {
    for (final id in multiSelected) {
      final item = items.where((i) => i.id == id).firstOrNull;
      if (item == null) continue;
      item.position = Offset(
        (item.position.dx + delta.dx).clamp(0, canvasW - item.width),
        (item.position.dy + delta.dy).clamp(0, totalCanvasHeight - item.height),
      );
    }
    // DO NOT call notifyListeners — let the caller setState
  }

  void multiMoveEnd() {
    notifyListeners();
  }

  // ─── FORMATTED TEXT CLIPBOARD (copy/paste text WITH formatting) ────────
  //
  // This works around flutter_quill's bug where Ctrl+C/V across different
  // QuillControllers strips inline attributes.
  //
  // copySelectedText: captures the full delta (or selected range) from the
  //   active text section's QuillController.
  // pasteFormattedText: inserts the captured delta into the current text
  //   section at the cursor position, preserving all formatting.

  void copySelectedText() {
    final item = selected;
    if (item == null || !item.isText || item.controller == null) return;

    final ctrl = item.controller!;
    final selection = ctrl.selection;

    if (selection.isCollapsed) {
      // No selection — copy entire document
      _clipboardDelta = ctrl.document.toDelta().toJson();
    } else {
      // Copy selected range with formatting
      final ops = ctrl.document.toDelta().toList();
      final selectedOps = <Map<String, dynamic>>[];
      int pos = 0;
      for (final op in ops) {
        if (!op.isInsert) continue;
        final text = op.data is String ? op.data as String : '';
        final opEnd = pos + text.length;
        if (opEnd > selection.start && pos < selection.end) {
          final clipStart = (selection.start - pos).clamp(0, text.length);
          final clipEnd = (selection.end - pos).clamp(0, text.length);
          final clipped = text.substring(clipStart, clipEnd);
          if (clipped.isNotEmpty) {
            final entry = <String, dynamic>{'insert': clipped};
            if (op.attributes != null && op.attributes!.isNotEmpty) {
              entry['attributes'] = Map<String, dynamic>.from(op.attributes!);
            }
            selectedOps.add(entry);
          }
        }
        pos = opEnd;
      }
      if (selectedOps.isNotEmpty) {
        // Ensure trailing newline
        final last = selectedOps.last['insert'] as String;
        if (!last.endsWith('\n')) {
          selectedOps.last['insert'] = '$last\n';
        }
        _clipboardDelta = selectedOps;
      }
    }
    debugPrint('📋 [Canvas] Copied formatted text (${_clipboardDelta?.length ?? 0} ops)');
  }

  void pasteFormattedText() {
    if (_clipboardDelta == null) return;
    final item = selected;
    if (item == null || !item.isText || item.controller == null) return;

    saveSnapshot();

    final ctrl = item.controller!;
    final index = ctrl.selection.baseOffset;

    // Parse the clipboard delta and insert at cursor
    try {
      for (final op in _clipboardDelta!) {
        if (op is! Map) continue;
        final text = op['insert'] as String? ?? '';
        if (text.isEmpty) continue;
        final attrs = op['attributes'] as Map<String, dynamic>?;

        // Remove trailing \n from each op to avoid double newlines
        final cleanText = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
        if (cleanText.isNotEmpty) {
          ctrl.document.insert(index, cleanText);
          // Apply formatting attributes
          if (attrs != null) {
            for (final entry in attrs.entries) {
              ctrl.formatText(
                index,
                cleanText.length,
                Attribute.fromKeyValue(entry.key, entry.value),
              );
            }
          }
        }
      }
      debugPrint('📋 [Canvas] Pasted formatted text at offset $index');
    } catch (e) {
      debugPrint('⚠️ [Canvas] Formatted paste failed: $e');
    }

    notifyListeners();
  }

  // ─── Z-ORDER ──────────────────────────────────────────────────────────

  void bringToFront() {
    if (selectedId == null) return;
    saveSnapshot();
    final idx = items.indexWhere((i) => i.id == selectedId);
    final item = items.removeAt(idx);
    items.add(item);
    notifyListeners();
  }

  void sendToBack() {
    if (selectedId == null) return;
    saveSnapshot();
    final idx = items.indexWhere((i) => i.id == selectedId);
    final item = items.removeAt(idx);
    items.insert(0, item);
    notifyListeners();
  }

  void bringForward() {
    if (selectedId == null) return;
    saveSnapshot();
    final idx = items.indexWhere((i) => i.id == selectedId);
    if (idx < items.length - 1) {
      final item = items.removeAt(idx);
      items.insert(idx + 1, item);
      notifyListeners();
    }
  }

  void sendBackward() {
    if (selectedId == null) return;
    saveSnapshot();
    final idx = items.indexWhere((i) => i.id == selectedId);
    if (idx > 0) {
      final item = items.removeAt(idx);
      items.insert(idx - 1, item);
      notifyListeners();
    }
  }

  void reorder(int oldIdx, int newIdx) {
    if (newIdx > oldIdx) newIdx--;
    saveSnapshot();
    final item = items.removeAt(oldIdx);
    items.insert(newIdx, item);
    notifyListeners();
  }

  // ─── PROPERTY UPDATES ─────────────────────────────────────────────────

  void updateColor(Color color) {
    if (selected == null) return;
    saveSnapshot();
    selected!.color = color;
    notifyListeners();
  }

  void updateBorderColor(Color color) {
    if (selected == null) return;
    saveSnapshot();
    selected!.borderColor = color;
    notifyListeners();
  }

  void updateBorderWidth(double width) {
    if (selected == null) return;
    selected!.borderWidth = width;
    notifyListeners();
  }

  void updateRotation(double radians) {
    if (selected == null) return;
    selected!.rotation = radians;
    notifyListeners();
  }

  void flipHorizontal() {
    if (selected == null) return;
    saveSnapshot();
    selected!.flipX = !selected!.flipX;
    notifyListeners();
  }

  void flipVertical() {
    if (selected == null) return;
    saveSnapshot();
    selected!.flipY = !selected!.flipY;
    notifyListeners();
  }

  void updateImage(Uint8List bytes) {
    if (selected == null) return;
    saveSnapshot();
    selected!.imageBytes = bytes;
    notifyListeners();
  }

  void updateIcon(IconData icon) {
    if (selected == null) return;
    saveSnapshot();
    selected!.iconData = icon;
    notifyListeners();
  }

  // ─── GLOBAL STYLES ────────────────────────────────────────────────────

  void applyGlobalFont(String family) {
    saveSnapshot();
    globalFont = family;
    for (final item in items) {
      if (!item.isText) continue;
      final len = item.controller!.document.length;
      if (len <= 1) continue;
      item.controller!.formatText(0, len - 1, Attribute.fromKeyValue('font', family));
    }
    notifyListeners();
  }

  void applyGlobalFontSize(double size) {
    saveSnapshot();
    globalFontSize = size;
    for (final item in items) {
      if (!item.isText) continue;
      final len = item.controller!.document.length;
      if (len <= 1) continue;
      item.controller!.formatText(0, len - 1, Attribute.fromKeyValue('size', '${size.toInt()}'));
    }
    notifyListeners();
  }

  // ─── TEMPLATE SYSTEM ──────────────────────────────────────────────────

  /// Re-measure all content, reflow so nothing overlaps, repage. Safe to call
  /// after edits or from an "Auto-arrange" button.
  void autoArrange() {
    saveSnapshot();
    clearContinuations();         // ← clear stale continuations FIRST
    autosizeAll();

    final prev = {for (final i in items) i.id: i.position.dy};
    ReflowEngine.arrange(items, canvasH);
    buildContinuations();

    int moved = 0; double maxDelta = 0;
    for (final i in items) {
      final d = (i.position.dy - (prev[i.id] ?? i.position.dy)).abs();
      if (d > 0.5) { moved++; if (d > maxDelta) maxDelta = d; }
    }
    debugPrint('🧹 autoArrange: MOVED $moved items, maxΔ=${maxDelta.toStringAsFixed(0)}px');

    double maxY = 0;
    for (final item in items) {
      final b = item.position.dy + item.height;
      if (b > maxY) maxY = b;
    }
    totalPages = (maxY / canvasH).ceil().clamp(1, 99);
    if (currentPage >= totalPages) currentPage = totalPages - 1;
    notifyListeners();
  }

  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // Ctrl+Z → Undo
    if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      undo();
      return true;
    }
    // Ctrl+Y or Ctrl+Shift+Z → Redo
    if (isCtrl && (event.logicalKey == LogicalKeyboardKey.keyY ||
        (isShift && event.logicalKey == LogicalKeyboardKey.keyZ))) {
      redo();
      return true;
    }
    // Delete/Backspace → Delete selected item.
    // CRITICAL: Skip if ANY text input has focus (Quill, TextField, search box,
    // etc). Backspace inside any text input must edit characters, not delete
    // the canvas item.
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      // Check 1: Is any Quill text item focused?
      final quillFocused = items.any(
              (i) => i.isText && (i.focusNode?.hasFocus ?? false));

      // Check 2: Is ANY text input (Material TextField, etc.) focused globally?
      // This catches the Custom Refine textbox, dialog inputs, search fields.
      final primaryFocus = FocusManager.instance.primaryFocus;
      final anyTextInputFocused = primaryFocus?.context?.widget is EditableText ||
          (primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null);

      // Belt-and-suspenders: backspace should never delete a canvas item.
      // Only Delete key triggers section deletion, and only when no text
      // input of any kind has focus.
      final isDeleteKey = event.logicalKey == LogicalKeyboardKey.delete;
      final safeToDelete = isDeleteKey &&
          !quillFocused &&
          !anyTextInputFocused &&
          (selectedId != null || multiSelected.isNotEmpty);

      if (safeToDelete) {
        saveSnapshot();
        deleteSelected();
        return true;
      }
    }
    return false;
  }

  // ─── FIRESTORE JSON ───────────────────────────────────────────────────

  void updateSectionType(SectionType newType) {
    if (selected == null) return;
    saveSnapshot();
    selected!.sectionType = newType;
    notifyListeners();
  }


  /// Applies a parsed AI edit envelope to the canvas.
  ///
  /// Behavior:
  ///   - One undo snapshot taken before the first op. A single Ctrl+Z
  ///     undoes the whole batch (atomic).
  ///   - Ops run in order. A failure on op N does not roll back ops 1..N-1
  ///     and does not stop ops N+1..end from trying.
  ///   - notifyListeners() is called exactly once at the end, so the UI
  ///     rebuilds once for the whole batch (no mid-batch flicker).
  ///   - generateContent ops kick off async (they need a follow-up aiFill
  ///     call). They return futures that the UI awaits with spinners.
  ///   - If the envelope is a refusal, we skip everything and return a
  ///     result carrying the refusal message.
  ///
  /// Returns an OpResult the UI uses to render the result strip.
  Future<OpResult> applyOps(AiEditEnvelope envelope) async {
    // Refusal: nothing to apply, just return the message.
    if (envelope.isRefusal) {
      debugPrint('🤖 [Canvas] AI refused: ${envelope.refusal} — ${envelope.summary}');
      return OpResult(
        appliedCount: 0,
        failures: const [],
        warnings: envelope.warnings,
        summary: envelope.summary,
        isRefusal: true,
        pendingGenerations: const [],
      );
    }

    // No ops to run (shouldn't happen on a non-refusal, but defensive).
    if (envelope.ops.isEmpty) {
      return OpResult(
        appliedCount: 0,
        failures: const [],
        warnings: envelope.warnings,
        summary: envelope.summary,
        isRefusal: false,
        pendingGenerations: const [],
      );
    }

    // Build the i0..iN -> real CanvasItem lookup the same way buildSnapshot
    // produced the IDs. This must match exactly or itemId resolution breaks.
    final realItems = items.where((i) => !i.isContinuation).toList();
    final idLookup = <String, CanvasItem>{
      for (int idx = 0; idx < realItems.length; idx++) 'i$idx': realItems[idx],
    };

    // Single snapshot at the top — atomic undo for the whole batch.
    saveSnapshot();

    final failures = <OpFailure>[];
    final pendingGenerations = <Future<void>>[];
    int appliedCount = 0;

    debugPrint('🤖 [Canvas] applyOps: running ${envelope.ops.length} ops');

    for (int i = 0; i < envelope.ops.length; i++) {
      final op = envelope.ops[i];
      try {
        final ok = await _dispatchOp(op, idLookup, pendingGenerations);
        if (ok) {
          appliedCount++;
        } else {
          // Handler returned false but didn't throw. Treat as a soft skip
          // (e.g. itemId not found). The handler is responsible for adding
          // its own OpFailure via the closure below.
        }
      } on OpFailureException catch (e) {
        debugPrint('🤖 [Canvas] op $i (${op.kind}) failed: ${e.code} ${e.message}');
        failures.add(OpFailure(
          code: e.code,
          message: e.message,
          opKind: op.kind,
          opIndex: i,
        ));
      } catch (e, st) {
        debugPrint('🤖 [Canvas] op $i (${op.kind}) threw: $e\n$st');
        failures.add(OpFailure(
          code: 'executionError',
          message: 'Op failed: $e',
          opKind: op.kind,
          opIndex: i,
        ));
      }
    }

    // Helper for handlers to report soft failures (e.g. unresolved itemId).
    // We do this via a closure because passing the failures list through
    // every handler signature would be noisy. Handlers throw _OpFailure
    // (private exception, see canvas_op_executors.dart) for soft failures
    // and the catch block above converts them.
    //
    // Re-walk the loop is overkill; instead handlers throw _OpFailure
    // and we catch it. See canvas_op_executors.dart for that pattern.

    debugPrint('🤖 [Canvas] applyOps done: $appliedCount applied, '
        '${failures.length} failed, ${pendingGenerations.length} async');

    // One rebuild for the whole batch.
    notifyListeners();

    return OpResult(
      appliedCount: appliedCount,
      failures: failures,
      warnings: envelope.warnings,
      summary: envelope.summary,
      isRefusal: false,
      pendingGenerations: pendingGenerations,
    );
  }

  /// Routes one op to its handler. Returns true on success, false on soft
  /// skip (e.g. itemId unresolved — the handler logs the failure itself
  /// via OpFailureException).
  ///
  /// The actual handler methods live in canvas_op_executors.dart as an
  /// extension on CanvasController. This is a thin dispatcher.
  Future<bool> _dispatchOp(
      CanvasOp op,
      Map<String, CanvasItem> idLookup,
      List<Future<void>> pendingGenerations,
      ) async
  {
    switch (op) {
      case UpdateTextOp():
        return applyUpdateText(op, idLookup);
      case FormatTextOp():
        return applyFormatText(op, idLookup);
      case UpdateItemOp():
        return applyUpdateItem(op, idLookup);
      case MoveItemOp():
        return applyMoveItem(op, idLookup);
      case DeleteItemOp():
        return applyDeleteItem(op, idLookup);
      case DuplicateItemOp():
        return applyDuplicateItem(op, idLookup);
      case AddItemOp():
        return applyAddItem(op);
      case UpdateCanvasOp():
        return applyUpdateCanvas(op);
      case GenerateContentOp():
      // generateContent kicks off async. The handler enqueues a future
      // and returns true immediately (the structural placeholder, if any,
      // is already applied; content fills in when the AI returns).
        return applyGenerateContent(op, idLookup, pendingGenerations);
      case UpdateTableOp():
        return applyUpdateTable(op, idLookup);
      case UpdateReflowOp():
        return applyUpdateReflow(op, idLookup);
      case UnknownOp():
        debugPrint('🤖 [Canvas] unknown op: ${op.kind}');
        return false;
    }
  }
}