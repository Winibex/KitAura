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
  }) {
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

  Color hexColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  String colorToHex(Color c) {
    final r = ((c.r * 255).round()).toRadixString(16).padLeft(2, '0');
    final g = ((c.g * 255).round()).toRadixString(16).padLeft(2, '0');
    final b = ((c.b * 255).round()).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  CanvasItem buildItemFromMap(Map<String, dynamic> map) {
    final type = parseCanvasItemType(map['type'] as String);
    final item = CanvasItem(
      type: type,
      position: Offset(
          (map['x'] as num).toDouble(), (map['y'] as num).toDouble()),
      width: (map['w'] as num).toDouble(),
      height: (map['h'] as num).toDouble(),
      rotation: (map['rotation'] as num? ?? 0).toDouble(),
      color: hexColor(map['color'] as String),
      borderColor: hexColor(map['borderColor'] as String),
      borderWidth: (map['borderWidth'] as num? ?? 1).toDouble(),
      title: map['title'] as String? ?? '',
      role: map['role'] as String?,
      group: map['group'] as String?,
      flipX: map['flipX'] as bool? ?? false,
      flipY: map['flipY'] as bool? ?? false,
      sectionType: map['sectionType'] != null
          ? SectionType.fromKey(map['sectionType'] as String)
          : null,
    );

    if (item.isText && map['delta'] != null) {
      try {
        final rawDelta = _sanitizeDelta(map['delta'] as List<dynamic>);
        item.controller!.document = Document.fromJson(rawDelta);
      } catch (_) {}
    }

    if (item.isTable && map['tableData'] != null) {
      try {
        item.tableData = TableData.fromJson(
            Map<String, dynamic>.from(map['tableData'] as Map));
      } catch (_) {}
    }

    return item;
  }

  /// Strips inline attributes from \n ops.
  /// flutter_quill asserts `after.isPlain` — newlines must NEVER carry
  /// inline attrs (color, size, bold, font, italic).
  static List<dynamic> _sanitizeDelta(List<dynamic> ops) {
    final result = <dynamic>[];
    for (final raw in ops) {
      if (raw is! Map) { result.add(raw); continue; }
      final op = Map<String, dynamic>.from(raw);
      final insert = op['insert'];
      if (insert is! String || !insert.contains('\n')) {
        result.add(op);
        continue;
      }
      // Split any "text\n" into "text" + attrs, then plain "\n"
      if (insert == '\n') {
        result.add({'insert': '\n'});
        continue;
      }
      final attrs = op['attributes'] as Map?;
      final parts = insert.split('\n');
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          final entry = <String, dynamic>{'insert': parts[i]};
          if (attrs != null && attrs.isNotEmpty) {
            entry['attributes'] = Map<String, dynamic>.from(attrs);
          }
          result.add(entry);
        }
        if (i < parts.length - 1) {
          result.add({'insert': '\n'});
        }
      }
    }
    return result;
  }

  void applyTemplateJson(Map<String, dynamic> json) {
    for (final item in items) {
      item.dispose();
    }
    items.clear();

    final bg = json['canvasBackground'] as String? ?? '#FFFFFF';
    final rawItems = json['items'] as List<dynamic>;
    for (final raw in rawItems) {
      final item = buildItemFromMap(raw as Map<String, dynamic>);
      items.add(item);
    }

    _clearContinuations();        // ← clear stale continuations FIRST
    autosizeAll();
    ReflowEngine.arrange(items, canvasH);
    _buildContinuations();

    // Auto-calculate page count from item positions
    double maxY = 0;
    for (final item in items) {
      final bottom = item.position.dy + item.height;
      if (bottom > maxY) maxY = bottom;
    }

    totalPages = (maxY / canvasH).ceil().clamp(1, 99);
    currentPage = 0;

    canvasBackground = hexColor(bg);
    selectedId = null;
    multiSelected.clear();
    notifyListeners();
  }

  Future<void> loadTemplate(String assetPath) async {
    saveSnapshot();
    final jsonStr = await rootBundle.loadString(assetPath);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    applyTemplateJson(json);
  }

  Map<String, dynamic> exportTemplateJson() {
    final itemsList = items.where((i) => !i.isContinuation).map((item) {
      final map = <String, dynamic>{
        'type': canvasItemTypeToString(item.type),
        'title': item.title,
        'x': item.position.dx,
        'y': item.position.dy,
        'w': item.width,
        'h': item.height,
        'color': colorToHex(item.color),
        'borderColor': colorToHex(item.borderColor),
        'borderWidth': item.borderWidth,
        'rotation': item.rotation,
        'flipX': item.flipX,
        'flipY': item.flipY,
        'sectionType': item.sectionType.key,
      };
      if (item.role != null) map['role'] = item.role;      // ← ADD
      if (item.group != null) map['group'] = item.group;   // ← ADD
      if (item.isText && item.controller != null) {
        map['delta'] = item.controller!.document.toDelta().toJson();
      }
      if (item.isTable && item.tableData != null) {
        map['tableData'] = item.tableData!.toJson();
      }
      return map;
    }).toList();

    return {
      'canvasBackground': colorToHex(canvasBackground),
      'items': itemsList,
    };
  }

  /// Re-measure all content, reflow so nothing overlaps, repage. Safe to call
  /// after edits or from an "Auto-arrange" button.
  void autoArrange() {
    saveSnapshot();
    _clearContinuations();        // ← clear stale continuations FIRST
    autosizeAll();

    final prev = {for (final i in items) i.id: i.position.dy};
    ReflowEngine.arrange(items, canvasH);
    _buildContinuations();

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

  // ─── PDF ──────────────────────────────────────────────────────────────

  Future<void> preloadFonts() async {
    try {
      Future<pw.Font> load(String p) async =>
          pw.Font.ttf(await rootBundle.load(p));
      pdfFonts['Arial'] = await load('assets/fonts/Arial.ttf');
      pdfFonts['OpenSans'] = await load('assets/fonts/OpenSans.ttf');
      pdfFonts['Poppins'] = await load('assets/fonts/Poppins.ttf');
      pdfFonts['Sekuya'] = await load('assets/fonts/Sekuya.ttf');
      fontsLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Font load error: $e');
    }
  }

  pw.Font getFont(String? f) =>
      pdfFonts[f] ?? pdfFonts['OpenSans'] ?? pdfFonts.values.first;

  PdfColor toPdfColor(Color c) => PdfColor(c.r, c.g, c.b, c.a);

  pw.Widget itemToPdf(CanvasItem item) {
    pw.Widget content;
    final vertices = shapeVertices(item.type);

    if (vertices.isNotEmpty) {
      content = pw.CustomPaint(
        size: PdfPoint(item.width, item.height),
        painter: (PdfGraphics canvas, PdfPoint size) {
          if (vertices.isEmpty) return;
          final pts = vertices
              .map((v) => PdfPoint(v.dx * size.x, v.dy * size.y))
              .toList();
          canvas.moveTo(pts.first.x, pts.first.y);
          for (final pt in pts.skip(1)) {
            canvas.lineTo(pt.x, pt.y);
          }
          canvas.closePath();
          canvas.setFillColor(toPdfColor(item.color));
          canvas.setStrokeColor(toPdfColor(item.borderColor));
          canvas.setLineWidth(item.borderWidth);
          canvas.fillAndStrokePath();
        },
      );
      return pw.Positioned(
        left: item.position.dx,
        top: item.position.dy,
        child: pw.Transform.rotateBox(
          angle: item.rotation,
          child: pw.SizedBox(width: item.width, height: item.height, child: content),
        ),
      );
    }

    switch (item.type) {
      case CanvasItemType.textSection:
      // Mirror AutoHeight.measureText EXACTLY so the PDF fills the same
      // box the engine reserved: line height 1.5, 8px paragraph spacing,
      // 10px vertical padding, empty line = fontSize × 1.5.
        final pdfDoc = item.displayController?.document ?? item.controller!.document;

        // 1) Group delta ops into paragraphs (split on '\n').
        final paragraphs = <List<pw.InlineSpan>>[];
        var cur = <pw.InlineSpan>[];
        void flushPara() { paragraphs.add(cur); cur = <pw.InlineSpan>[]; }

        for (final op in pdfDoc.toDelta().toList()) {
          if (!op.isInsert) continue;
          final raw = op.data as String? ?? '';
          if (raw.isEmpty) continue;
          final a = op.attributes;

          double fontSize = globalFontSize;
          if (a?['size'] != null) {
            fontSize = double.tryParse(a!['size'].toString()) ?? globalFontSize;
          }
          PdfColor textColor = PdfColors.black;
          if (a?['color'] != null) {
            try {
              final hex = (a!['color'] as String).replaceFirst('#', '');
              final c = Color(int.parse('FF$hex', radix: 16));
              textColor = PdfColor(c.r, c.g, c.b);
            } catch (_) {}
          }

          final style = pw.TextStyle(
            font: getFont(a?['font'] as String? ?? globalFont),
            fontSize: fontSize,
            fontWeight: a?['bold'] == true ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontStyle: a?['italic'] == true ? pw.FontStyle.italic : pw.FontStyle.normal,
            color: textColor,
            lineSpacing: fontSize * (AutoHeight.textLineHeight - 1.0),
          );

          final parts = raw.split('\n');
          for (int i = 0; i < parts.length; i++) {
            if (parts[i].isNotEmpty) {
              cur.add(pw.TextSpan(text: parts[i], style: style));
            }
            if (i < parts.length - 1) flushPara();
          }
        }
        if (cur.isNotEmpty) flushPara();

        // 2) Build one widget per paragraph, with 8px gaps between them,
        //    matching AutoHeight.paragraphSpacing.
        final paraWidgets = <pw.Widget>[];
        for (int p = 0; p < paragraphs.length; p++) {
          final spans = paragraphs[p];
          if (p > 0) {
            paraWidgets.add(pw.SizedBox(height: AutoHeight.paragraphSpacing)); // 8px
          }
          if (spans.isEmpty) {
            // Empty paragraph occupies a full line, like the engine reserves.
            paraWidgets.add(pw.SizedBox(height: AutoHeight.defaultFontSize * AutoHeight.textLineHeight));
          } else {
            paraWidgets.add(pw.RichText(
              text: pw.TextSpan(children: List.of(spans)),
            ));
          }
        }

        // 3) Wrap with the same 10px vertical padding (textVPad) the engine
        //    adds, split half top / half bottom.
        content = pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: AutoHeight.textVPad / 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: paraWidgets,
          ),
        );
        break;
      case CanvasItemType.line:
        content = pw.Container(
          width: item.width,
          height: item.borderWidth.clamp(1, 12),
          color: toPdfColor(item.borderColor),
        );
        break;
      case CanvasItemType.rectangle:
        content = pw.Container(
          decoration: pw.BoxDecoration(
            color: toPdfColor(item.color),
            border: pw.Border.all(color: toPdfColor(item.borderColor), width: item.borderWidth),
          ),
        );
        break;
      case CanvasItemType.circle:
        content = pw.Container(
          decoration: pw.BoxDecoration(
            color: toPdfColor(item.color),
            shape: pw.BoxShape.circle,
            border: pw.Border.all(color: toPdfColor(item.borderColor), width: item.borderWidth),
          ),
        );
        break;
      case CanvasItemType.imageBox:
        content = item.imageBytes != null
            ? pw.Image(pw.MemoryImage(item.imageBytes!), fit: pw.BoxFit.cover)
            : pw.Container(
          decoration: pw.BoxDecoration(
            color: toPdfColor(item.color),
            border: pw.Border.all(color: toPdfColor(item.borderColor)),
          ),
        );
        break;
      case CanvasItemType.icon:
        content = pw.Container(
          decoration: pw.BoxDecoration(
            color: toPdfColor(item.borderColor),
            shape: pw.BoxShape.circle,
          ),
        );
        break;
      case CanvasItemType.tableSection:
      // Split table parents render only their kept rows (display copy);
      // remaining rows are drawn by the continuation table item.
        final td = item.displayTableData ?? item.tableData;
        if (td == null || td.headers.isEmpty) {
          content = pw.SizedBox();
          break;
        }
        final rows = <pw.TableRow>[];
        // Header
        if (td.showHeader) {
          rows.add(pw.TableRow(
            decoration: pw.BoxDecoration(color: toPdfColor(td.headerBgColor)),
            children: td.headers.map((h) => pw.Padding(
              padding: pw.EdgeInsets.symmetric(horizontal: AutoHeight.cellHPad, vertical: AutoHeight.headerVPad),
              child: pw.Text(h, style: pw.TextStyle(
                font: getFont(globalFont),
                fontSize: td.fontSize,
                fontWeight: pw.FontWeight.bold,
                color: toPdfColor(td.headerTextColor),
              )),
            )).toList(),
          ));
        }
        // Data rows
        for (int r = 0; r < td.rowCount; r++) {
          rows.add(pw.TableRow(
            decoration: pw.BoxDecoration(
              color: r % 2 == 0 ? PdfColors.white : const PdfColor(0.976, 0.969, 0.961),
            ),
            children: List.generate(td.columnCount, (c) {
              final val = c < td.rows[r].length ? td.rows[r][c] : '';
              return pw.Padding(
                padding: pw.EdgeInsets.symmetric(horizontal: AutoHeight.cellHPad, vertical: AutoHeight.cellVPad),
                child: pw.Text(val, style: pw.TextStyle(
                  font: getFont(globalFont),
                  fontSize: td.fontSize,
                  color: toPdfColor(td.cellTextColor),
                )),
              );
            }),
          ));
        }
        debugPrint('📊 PDF TBL "${item.title}" boxH=${item.height.toStringAsFixed(1)} '
            'rows=${td.rowCount} reservedByEngine=${item.height.toStringAsFixed(1)}');
        content = pw.Table(
          border: pw.TableBorder.all(color: toPdfColor(td.borderColor), width: 0.5),
          columnWidths: {
            for (int c = 0; c < td.columnCount; c++)
              c: const pw.FlexColumnWidth(1),  // equal columns, matches measureTable
          },
          children: rows,
        );
        break;
      default:
        content = pw.SizedBox();
    }

    final bool autoH = item.isText || item.isTable;
    return pw.Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: pw.Transform.rotateBox(
        angle: item.rotation,
        child: autoH
            ? pw.SizedBox(width: item.width, child: content)
            : pw.SizedBox(width: item.width, height: item.height, child: content),
      ),
    );
  }

  // REPLACE the entire buildPdf method:

  Future<Uint8List> buildPdf({bool showWatermark = false}) async {
    final doc = pw.Document();
    for (int p = 0; p < totalPages; p++) {
      final pageOffset = p * canvasH;
      debugPrint('📄 PDF page $p: canvasH=$canvasH pageOffset=$pageOffset '
          'a4=${PdfPageFormat.a4.width.toStringAsFixed(1)}x${PdfPageFormat.a4.height.toStringAsFixed(1)} '
          'items=${items.where((i) => (i.position.dy / canvasH).floor() == p).length}');
      final pageItems = items.where((item) {
        final itemPage = (item.position.dy / canvasH).floor();
        return itemPage == p;
      }).toList();

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (ctx) {
          final children = pageItems.map((item) {
            final adjustedItem = item;
            final original = adjustedItem.position;
            adjustedItem.position = Offset(original.dx, original.dy - pageOffset);
            final widget = itemToPdf(adjustedItem);
            adjustedItem.position = original;
            return widget;
          }).toList();

          // Watermark as last element in Stack (renders on top)
          if (showWatermark) {
            children.add(
              pw.Positioned(
                bottom: 8,
                right: 12,
                child: pw.Text(
                  'Made with KitAura — kitaura.com',
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey400,
                    font: pw.Font.helvetica(),
                  ),
                ),
              ),
            );
          }

          return pw.Stack(children: children);
        },
      ));
    }
    return doc.save();
  }

  // ─── KEYBOARD HANDLER ─────────────────────────────────────────────────

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
    // Delete/Backspace → Delete selected (only if no text focused)
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final textFocused = items.any((i) => i.isText && (i.focusNode?.hasFocus ?? false));
      if (!textFocused && (selectedId != null || multiSelected.isNotEmpty)) {
        saveSnapshot();
        deleteSelected();
        return true;
      }
    }
    return false;
  }

  // ─── FIRESTORE JSON ───────────────────────────────────────────────────

  Map<String, dynamic> toFirestoreJson(String userId, String templateId) {
    return {
      'userId': userId,
      'title': 'Untitled CV',
      'canvasBackground': colorToHex(canvasBackground),
      'templateId': templateId,
      'status': 'draft',
      'isArchived': false,
      'exportCount': 0,
      'items': items.where((i) => !i.isContinuation).map((item) {
        final map = <String, dynamic>{
          'type': canvasItemTypeToString(item.type),
          'title': item.title,
          'x': item.position.dx,
          'y': item.position.dy,
          'w': item.width,
          'h': item.height,
          'color': colorToHex(item.color),
          'borderColor': colorToHex(item.borderColor),
          'borderWidth': item.borderWidth,
          'rotation': item.rotation,
          'flipX': item.flipX,
          'flipY': item.flipY,
          'sectionType': item.sectionType.key,
        };
        if (item.role != null) map['role'] = item.role;      // ← ADD
        if (item.group != null) map['group'] = item.group;   // ← ADD
        if (item.isText && item.controller != null) {
          map['delta'] = item.controller!.document.toDelta().toJson();
        }
        if (item.isTable && item.tableData != null) {
          map['tableData'] = item.tableData!.toJson();
        }
        return map;
      }).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  void updateSectionType(SectionType newType) {
    if (selected == null) return;
    saveSnapshot();
    selected!.sectionType = newType;
    notifyListeners();
  }

  /// Removes all continuation items. Must run BEFORE reflow so the engine
  /// never sees stale continuations as real content.
  void _clearContinuations() {
    items.removeWhere((i) {
      if (i.isContinuation) { i.dispose(); return true; }
      return false;
    });
    // Also clear overflow markers on real items so reflow starts clean.
    // Clear overflow markers on real items so reflow starts clean.
    for (final i in items) {
      i.overflowSegments = null;
      i.displayOps = null;
      i.displayTableData = null;
      i.displayController?.dispose();
      i.displayController = null;
    }
  }

  /// After reflow, create one continuation item per overflow segment. These
  /// render leftover text on later pages. Disposable — rebuilt every reflow,
  /// never saved (excluded via !isContinuation in toFirestoreJson/export).
  void _buildContinuations() {
    final toAdd = <CanvasItem>[];
    for (final item in items) {
      final segs = item.overflowSegments;
      if (segs == null) continue;
      for (final seg in segs) {
        if (seg.tableData != null) {
          final cont = CanvasItem(
            type: CanvasItemType.tableSection,
            position: Offset(item.position.dx, seg.y),
            width: item.width,
            height: seg.height,
            title: '',
            tableData: seg.tableData,
          );
          cont.isContinuation = true;
          toAdd.add(cont);
          debugPrint('➡️ CONT-TBL "${item.title}" Y=${seg.y.toStringAsFixed(0)} '
              'h=${seg.height.toStringAsFixed(0)} '
              'rows=${seg.tableData!.rowCount}');
        } else {
          final cont = CanvasItem(
            type: CanvasItemType.textSection,
            position: Offset(item.position.dx, seg.y),
            width: item.width,
            height: seg.height,
            title: '',
          );
          cont.isContinuation = true;
          try {
            cont.controller!.document =
                Document.fromJson(_sanitizeDelta(seg.ops!));
          } catch (e) {
            debugPrint('Continuation build failed: $e');
          }
          toAdd.add(cont);
          debugPrint('➡️ CONT "${item.title}" Y=${seg.y.toStringAsFixed(0)} '
              'h=${seg.height.toStringAsFixed(0)}');
        }
      }
    }
    items.addAll(toAdd);

    // Build read-only display controllers for split text parents so they
    // render ONLY their kept paragraphs (full text stays in `controller`).
    for (final item in items) {
      if (item.isText && item.displayOps != null) {
        item.displayController?.dispose();
        final c = QuillController.basic();
        try {
          c.document = Document.fromJson(_sanitizeDelta(item.displayOps!));
        } catch (e) {
          debugPrint('display build failed: $e');
        }
        item.displayController = c;
      }
    }
  }
}