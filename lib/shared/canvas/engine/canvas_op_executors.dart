// lib/shared/canvas/engine/canvas_op_executors.dart
//
// Extension on CanvasController providing the 11 AI op handler methods.
// Called from CanvasController.applyOps via the dispatcher.
//
// Each handler:
//   - Resolves the target item from the i0..iN lookup (if applicable).
//   - Mutates state directly (no per-op snapshot — applyOps took one at top).
//   - Throws OpFailureException for soft failures (logged as failures in
//     the OpResult, but the batch continues).
//   - Returns true on success, false on no-op-but-not-an-error.
//
// generateContent is the only async handler. It enqueues a future and the
// UI awaits it with a spinner.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../ai/claude_service.dart';
import '../../models/canvas_item.dart';
import '../../models/canvas_item_type.dart';
import '../../models/section_type.dart';
import '../../models/table_data.dart';
import 'canvas_controller.dart';
import 'canvas_op_types.dart';

// ════════════════════════════════════════════════════════════════════════
// Soft-failure exception — caught by applyOps, converted to OpFailure
// ════════════════════════════════════════════════════════════════════════

class OpFailureException implements Exception {
  final String code;
  final String message;
  OpFailureException(this.code, this.message);
  @override
  String toString() => '$code: $message';
}

// ════════════════════════════════════════════════════════════════════════
// EXTENSION — all 11 handlers + helpers live here
// ════════════════════════════════════════════════════════════════════════

extension CanvasOpExecutors on CanvasController {
  // ─── SHARED HELPERS ─────────────────────────────────────────────────

  /// Resolves an itemId (e.g. "i0") to a real CanvasItem. Throws if missing.
  CanvasItem _resolveItem(String itemId, Map<String, CanvasItem> lookup) {
    final item = lookup[itemId];
    if (item == null) {
      throw OpFailureException(
        'itemNotFound',
        'No item found for id "$itemId" (it may have been deleted).',
      );
    }
    return item;
  }

  /// Asserts the item is a text section. Used by text-only ops.
  void _requireText(CanvasItem item) {
    if (!item.isText || item.controller == null) {
      throw OpFailureException(
        'wrongItemType',
        'Expected a text section but got "${canvasItemTypeToString(item.type)}".',
      );
    }
  }

  /// Asserts the item is a table section. Used by updateTable.
  void _requireTable(CanvasItem item) {
    if (!item.isTable || item.tableData == null) {
      throw OpFailureException(
        'wrongItemType',
        'Expected a table but got "${canvasItemTypeToString(item.type)}".',
      );
    }
  }

  /// Defensive color parse — handles "#RGB", "#RRGGBB", "#AARRGGBB", or
  /// garbage. Returns null on failure so callers can decide to skip vs.
  /// keep current color.
  Color? _parseColorOrNull(String? hex) {
    if (hex == null) return null;
    var s = hex.trim().replaceFirst('#', '');
    if (s.length == 3) {
      // Expand "FFF" -> "FFFFFF"
      s = s.split('').map((c) => '$c$c').join();
    }
    if (s.length == 6) {
      try {
        return Color(int.parse('FF$s', radix: 16));
      } catch (_) {
        return null;
      }
    }
    if (s.length == 8) {
      try {
        return Color(int.parse(s, radix: 16));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Gets the (start, end) offset for a given line index in a Quill document.
  /// Returns null if the line index is out of range.
  /// Lines are split by '\n' in the plain text; Quill always has a trailing
  /// newline, which is treated as the end of the last line, not a new line.
  ({int start, int end})? _lineBounds(QuillController ctrl, int lineIndex) {
    final plain = ctrl.document.toPlainText();
    final lines = plain.split('\n');
    // Quill always has a trailing empty string after the final \n — drop it.
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    if (lineIndex < 0 || lineIndex >= lines.length) return null;

    int start = 0;
    for (int i = 0; i < lineIndex; i++) {
      start += lines[i].length + 1; // +1 for the \n
    }
    final end = start + lines[lineIndex].length;
    return (start: start, end: end);
  }

  // ─── 1. updateText ──────────────────────────────────────────────────
  Future<bool> applyUpdateText(
      UpdateTextOp op,
      Map<String, CanvasItem> lookup,
      ) async {
    final item = _resolveItem(op.itemId, lookup);
    _requireText(item);
    final ctrl = item.controller!;

    switch (op.mode) {
      case TextEditMode.replaceLine:
        if (op.lineIndex == null) {
          throw OpFailureException('invalidIndex', 'replaceLine needs lineIndex.');
        }
        final bounds = _lineBounds(ctrl, op.lineIndex!);
        if (bounds == null) {
          throw OpFailureException(
              'invalidIndex', 'Line ${op.lineIndex} is out of range.');
        }
        final newText = op.newText ?? '';
        ctrl.replaceText(
          bounds.start,
          bounds.end - bounds.start,
          newText,
          null, // selection
        );
        debugPrint('🤖 updateText.replaceLine: line ${op.lineIndex}');
        return true;

      case TextEditMode.deleteLine:
        if (op.lineIndex == null) {
          throw OpFailureException('invalidIndex', 'deleteLine needs lineIndex.');
        }
        final bounds = _lineBounds(ctrl, op.lineIndex!);
        if (bounds == null) {
          throw OpFailureException(
              'invalidIndex', 'Line ${op.lineIndex} is out of range.');
        }
        // Delete the line text + its trailing newline (if not the last line).
        final plain = ctrl.document.toPlainText();
        final totalLen = plain.length - 1; // ignore Quill's trailing \n
        final deleteLen = (bounds.end < totalLen)
            ? (bounds.end - bounds.start + 1)
            : (bounds.end - bounds.start);
        ctrl.replaceText(bounds.start, deleteLen, '', null);
        debugPrint('🤖 updateText.deleteLine: line ${op.lineIndex}');
        return true;

      case TextEditMode.insertLine:
        if (op.lineIndex == null) {
          throw OpFailureException('invalidIndex', 'insertLine needs lineIndex.');
        }
        final newText = op.newText ?? '';
        final plain = ctrl.document.toPlainText();
        final lines = plain.split('\n');
        if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
        // Clamp insertion point: insert at lineIndex means before that line.
        final idx = op.lineIndex!.clamp(0, lines.length);
        int insertAt = 0;
        for (int i = 0; i < idx; i++) {
          insertAt += lines[i].length + 1;
        }
        ctrl.replaceText(insertAt, 0, '$newText\n', null);
        debugPrint('🤖 updateText.insertLine: at $idx');
        return true;

      case TextEditMode.replaceRange:
        if (op.range == null || op.range!.length != 2) {
          throw OpFailureException(
              'invalidIndex', 'replaceRange needs a [start, end] range.');
        }
        final plain = ctrl.document.toPlainText();
        final maxLen = plain.length - 1;
        final start = op.range![0].clamp(0, maxLen);
        final end = op.range![1].clamp(start, maxLen);
        ctrl.replaceText(start, end - start, op.newText ?? '', null);
        debugPrint('🤖 updateText.replaceRange: [$start, $end]');
        return true;

      case TextEditMode.unknown:
        throw OpFailureException('invalidIndex', 'Unknown updateText mode.');
    }
  }

  // ─── 2. formatText ──────────────────────────────────────────────────
  Future<bool> applyFormatText(
      FormatTextOp op,
      Map<String, CanvasItem> lookup,
      ) async {
    final item = _resolveItem(op.itemId, lookup);
    _requireText(item);
    final ctrl = item.controller!;
    final attrs = op.attrs;
    if (attrs == null || attrs.isEmpty) {
      throw OpFailureException(
          'invalidIndex', 'formatText needs an attrs map.');
    }

    // Determine the range to format.
    int start = 0;
    int length = 0;
    final plain = ctrl.document.toPlainText();
    final docLen = plain.length - 1; // exclude trailing \n

    switch (op.scope) {
      case FormatScope.whole:
        start = 0;
        length = docLen;
        break;
      case FormatScope.line:
        if (op.lineIndex == null) {
          throw OpFailureException(
              'invalidIndex', 'formatText.line needs lineIndex.');
        }
        final bounds = _lineBounds(ctrl, op.lineIndex!);
        if (bounds == null) {
          throw OpFailureException(
              'invalidIndex', 'Line ${op.lineIndex} is out of range.');
        }
        start = bounds.start;
        length = bounds.end - bounds.start;
        break;
      case FormatScope.range:
        if (op.range == null || op.range!.length != 2) {
          throw OpFailureException(
              'invalidIndex', 'formatText.range needs a [start, end] range.');
        }
        start = op.range![0].clamp(0, docLen);
        final end = op.range![1].clamp(start, docLen);
        length = end - start;
        break;
      case FormatScope.unknown:
        throw OpFailureException(
            'invalidIndex', 'Unknown formatText scope.');
    }

    if (length <= 0) {
      // Nothing to format — not a failure, just a no-op.
      return true;
    }

    // Apply each attribute. Null value means "clear", value means "set".
    // Keys absent from the map are not touched.
    for (final entry in attrs.entries) {
      final key = entry.key;
      final value = entry.value;
      try {
        ctrl.formatText(
          start,
          length,
          Attribute.fromKeyValue(key, value),
        );
      } catch (e) {
        debugPrint('🤖 formatText: attr "$key" failed: $e');
      }
    }
    debugPrint('🤖 formatText: scope=${op.scope.name} attrs=${attrs.keys}');
    return true;
  }

  // ─── 3. updateItem ──────────────────────────────────────────────────
  Future<bool> applyUpdateItem(
      UpdateItemOp op,
      Map<String, CanvasItem> lookup,
      ) async {
    final item = _resolveItem(op.itemId, lookup);
    final p = op.props;
    if (p.isEmpty) return true; // no-op

    if (p.containsKey('color')) {
      final c = _parseColorOrNull(p['color'] as String?);
      if (c != null) item.color = c;
    }
    if (p.containsKey('borderColor')) {
      final c = _parseColorOrNull(p['borderColor'] as String?);
      if (c != null) item.borderColor = c;
    }
    if (p.containsKey('borderWidth')) {
      final v = (p['borderWidth'] as num?)?.toDouble();
      if (v != null) item.borderWidth = v.clamp(0, 50);
    }
    if (p.containsKey('rotation')) {
      // AI returns degrees; CanvasItem stores radians.
      final deg = (p['rotation'] as num?)?.toDouble();
      if (deg != null) item.rotation = deg * 3.141592653589793 / 180.0;
    }
    if (p.containsKey('flipX')) {
      final v = p['flipX'];
      if (v is bool) item.flipX = v;
    }
    if (p.containsKey('flipY')) {
      final v = p['flipY'];
      if (v is bool) item.flipY = v;
    }
    if (p.containsKey('w')) {
      final v = (p['w'] as num?)?.toDouble();
      if (v != null) item.width = v.clamp(10, CanvasController.canvasW);
    }
    if (p.containsKey('h')) {
      final v = (p['h'] as num?)?.toDouble();
      if (v != null) item.height = v.clamp(10, 9999);
    }
    debugPrint('🤖 updateItem: ${item.id} props=${p.keys}');
    return true;
  }

  // ─── 4. moveItem ────────────────────────────────────────────────────
  Future<bool> applyMoveItem(
      MoveItemOp op,
      Map<String, CanvasItem> lookup,
      ) async {
    final item = _resolveItem(op.itemId, lookup);

    // Priority: explicit x/y > align > dx/dy > toPage alone.
    double newX = item.position.dx;
    double newY = item.position.dy;

    // Page change: convert to a Y offset, preserving intra-page Y.
    if (op.toPage != null) {
      final targetPage = (op.toPage! - 1).clamp(0, 99); // 1-based to 0-based
      final currentPage = (item.position.dy / CanvasController.canvasH).floor();
      final intraY = item.position.dy - (currentPage * CanvasController.canvasH);
      newY = targetPage * CanvasController.canvasH + intraY;
    }

    // Explicit position (highest priority — overrides page math for Y).
    if (op.x != null) newX = op.x!;
    if (op.y != null) {
      // If user gave Y AND toPage, treat Y as intra-page on the target page.
      if (op.toPage != null) {
        final targetPage = (op.toPage! - 1).clamp(0, 99);
        newY = targetPage * CanvasController.canvasH + op.y!;
      } else {
        newY = op.y!;
      }
    }

    // Alignment (overrides x/y on the relevant axis).
    switch (op.align) {
      case MoveAlign.centerH:
        newX = (CanvasController.canvasW - item.width) / 2;
        break;
      case MoveAlign.centerV:
      // Center on the item's current page.
        final page = (newY / CanvasController.canvasH).floor();
        newY = page * CanvasController.canvasH +
            (CanvasController.canvasH - item.height) / 2;
        break;
      case MoveAlign.left:
        newX = 0;
        break;
      case MoveAlign.right:
        newX = CanvasController.canvasW - item.width;
        break;
      case MoveAlign.top:
        final page = (newY / CanvasController.canvasH).floor();
        newY = page * CanvasController.canvasH;
        break;
      case MoveAlign.bottom:
        final page = (newY / CanvasController.canvasH).floor();
        newY = (page + 1) * CanvasController.canvasH - item.height;
        break;
      case MoveAlign.none:
        break;
    }

    // Relative deltas — applied after absolute / align.
    if (op.dx != null) newX += op.dx!;
    if (op.dy != null) newY += op.dy!;

    // Clamp to canvas bounds.
    item.position = Offset(
      newX.clamp(0, CanvasController.canvasW - item.width),
      newY.clamp(0, totalCanvasHeight - item.height),
    );
    debugPrint('🤖 moveItem: ${item.id} -> (${item.position.dx.round()}, ${item.position.dy.round()})');
    return true;
  }

  // ─── 5. deleteItem ──────────────────────────────────────────────────
  Future<bool> applyDeleteItem(
      DeleteItemOp op,
      Map<String, CanvasItem> lookup,
      ) async {
    final item = _resolveItem(op.itemId, lookup);
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx == -1) {
      throw OpFailureException(
          'itemNotFound', 'Item gone from list (already removed).');
    }
    items[idx].dispose();
    items.removeAt(idx);
    if (selectedId == item.id) selectedId = null;
    debugPrint('🤖 deleteItem: ${item.id}');
    return true;
  }

  // ─── 6. duplicateItem ───────────────────────────────────────────────
  Future<bool> applyDuplicateItem(
      DuplicateItemOp op,
      Map<String, CanvasItem> lookup,
      ) async {
    final src = _resolveItem(op.itemId, lookup);
    final offsetY = op.offsetY ?? 20;

    double newX = src.position.dx;
    double newY = src.position.dy + offsetY;

    if (op.toPage != null) {
      final targetPage = (op.toPage! - 1).clamp(0, 99);
      final srcPage = (src.position.dy / CanvasController.canvasH).floor();
      final intraY = src.position.dy - (srcPage * CanvasController.canvasH);
      newY = targetPage * CanvasController.canvasH + intraY + offsetY;
    }

    final clone = CanvasItem(
      type: src.type,
      position: Offset(newX, newY),
      width: src.width,
      height: src.height,
      rotation: src.rotation,
      color: src.color,
      borderColor: src.borderColor,
      borderWidth: src.borderWidth,
      iconData: src.iconData,
      title: src.title,
      flipX: src.flipX,
      flipY: src.flipY,
      sectionType: src.sectionType,
      role: src.role,
      group: src.group,
    );
    if (src.isText && src.controller != null && clone.controller != null) {
      try {
        clone.controller!.document = Document.fromJson(
          src.controller!.document.toDelta().toJson(),
        );
      } catch (_) {}
    }
    if (src.isTable && src.tableData != null) {
      clone.tableData = src.tableData!.copyWith();
    }
    if (src.imageBytes != null) {
      clone.imageBytes = Uint8List.fromList(src.imageBytes!);
    }
    items.add(clone);
    debugPrint('🤖 duplicateItem: ${src.id} -> ${clone.id}');
    return true;
  }

  // ─── 7. addItem ─────────────────────────────────────────────────────
  Future<bool> applyAddItem(AddItemOp op) async {
    final CanvasItemType type;
    try {
      type = parseCanvasItemType(op.type);
    } catch (e) {
      throw OpFailureException(
          'invalidIndex', 'Unknown item type "${op.type}".');
    }

    // Resolve position. If page given, treat x/y as intra-page coords.
    final page = (op.page ?? 1).clamp(1, 99);
    final pageOffsetY = (page - 1) * CanvasController.canvasH;
    final x = (op.x ?? 40).clamp(0, CanvasController.canvasW.toDouble());
    final y = (op.y ?? 100).clamp(0, CanvasController.canvasH.toDouble());
    final w = (op.w ?? _defaultWidthFor(type))
        .clamp(10, CanvasController.canvasW.toDouble());
    final h = (op.h ?? _defaultHeightFor(type)).clamp(10, 9999);

    final color = _parseColorOrNull(op.color);

    if (type == CanvasItemType.textSection) {
      final sec = op.sectionType != null
          ? SectionType.fromKey(op.sectionType!)
          : SectionType.detectFromTitle(op.title ?? '');
      final item = CanvasItem(
        type: type,
        position: Offset(x.toDouble(), pageOffsetY + y.toDouble()),
        width: w.toDouble(),
        height: h.toDouble(),
        title: op.title ?? 'New Section',
        sectionType: sec,
        role: op.role,
        group: op.group,
      );
      if (op.initialText != null && op.initialText!.isNotEmpty && item.controller != null) {
        // Build a plain delta: text + trailing \n.
        final text = op.initialText!.endsWith('\n')
            ? op.initialText!
            : '${op.initialText!}\n';
        item.controller!.document = Document.fromDelta(
          Delta()..insert(text),
        );
      }
      items.add(item);
      debugPrint('🤖 addItem: textSection "${item.title}"');
      return true;
    }

    if (type == CanvasItemType.tableSection) {
      final item = CanvasItem(
        type: type,
        position: Offset(x.toDouble(), pageOffsetY + y.toDouble()),
        width: w.toDouble(),
        height: h.toDouble(),
        title: op.title ?? 'Table',
        sectionType: op.sectionType != null
            ? SectionType.fromKey(op.sectionType!)
            : SectionType.custom,
        role: op.role,
        group: op.group,
        tableData: TableData.empty(),
      );
      items.add(item);
      debugPrint('🤖 addItem: tableSection');
      return true;
    }

    // Shapes / lines / icons
    final defaults = _shapeDefaultsFor(type);
    final item = CanvasItem(
      type: type,
      position: Offset(x.toDouble(), pageOffsetY + y.toDouble()),
      width: w.toDouble(),
      height: h.toDouble(),
      color: color ?? defaults['color'] as Color,
      borderColor: defaults['border'] as Color,
      iconData: type == CanvasItemType.icon ? Icons.star : null,
      role: op.role,
      group: op.group,
    );
    items.add(item);
    debugPrint('🤖 addItem: ${canvasItemTypeToString(type)}');
    return true;
  }

  double _defaultWidthFor(CanvasItemType t) {
    switch (t) {
      case CanvasItemType.textSection:
        return 515;
      case CanvasItemType.tableSection:
        return 495;
      case CanvasItemType.line:
        return 200;
      case CanvasItemType.icon:
        return 48;
      default:
        return 160;
    }
  }

  double _defaultHeightFor(CanvasItemType t) {
    switch (t) {
      case CanvasItemType.textSection:
        return 80;
      case CanvasItemType.tableSection:
        return 160;
      case CanvasItemType.line:
        return 4;
      case CanvasItemType.icon:
        return 48;
      case CanvasItemType.rectangle:
        return 100;
      default:
        return 120;
    }
  }

  Map<String, dynamic> _shapeDefaultsFor(CanvasItemType t) {
    // Mirrors the defaults table in addShape() so AI-added shapes look the
    // same as menu-added shapes.
    switch (t) {
      case CanvasItemType.line:
        return {'color': Colors.transparent, 'border': Colors.black};
      case CanvasItemType.rectangle:
        return {
          'color': const Color(0xFFE3F2FD),
          'border': const Color(0xFF2196F3),
        };
      case CanvasItemType.circle:
        return {
          'color': const Color(0xFFE8F5E9),
          'border': const Color(0xFF4CAF50),
        };
      case CanvasItemType.imageBox:
        return {
          'color': const Color(0xFFF5F5F5),
          'border': const Color(0xFF9E9E9E),
        };
      case CanvasItemType.icon:
        return {'color': Colors.transparent, 'border': const Color(0xFF2196F3)};
      default:
        return {
          'color': const Color(0xFFFFF3E0),
          'border': const Color(0xFFFF9800),
        };
    }
  }

  // ─── 8. updateCanvas ────────────────────────────────────────────────
  Future<bool> applyUpdateCanvas(UpdateCanvasOp op) async {
    if (op.canvasBackground != null) {
      final c = _parseColorOrNull(op.canvasBackground);
      if (c != null) canvasBackground = c;
    }
    switch (op.pageAction) {
      case PageAction.add:
        totalPages++;
        debugPrint('🤖 updateCanvas: added page (total=$totalPages)');
        break;
      case PageAction.removeLast:
        if (totalPages > 1) {
          _removePageInternal(totalPages - 1);
          debugPrint('🤖 updateCanvas: removed last page');
        }
        break;
      case PageAction.removeAt:
        if (op.pageIndex != null) {
          final idx = op.pageIndex!;
          if (idx >= 0 && idx < totalPages && totalPages > 1) {
            _removePageInternal(idx);
            debugPrint('🤖 updateCanvas: removed page $idx');
          }
        }
        break;
      case PageAction.none:
        break;
    }
    return true;
  }

  /// Internal page removal — mirrors removePage() but skips notifyListeners
  /// (applyOps will call it once at the end).
  void _removePageInternal(int pageIndex) {
    items.removeWhere((item) {
      final p = (item.position.dy / CanvasController.canvasH).floor();
      if (p == pageIndex) {
        item.dispose();
        return true;
      }
      return false;
    });
    for (final item in items) {
      final p = (item.position.dy / CanvasController.canvasH).floor();
      if (p > pageIndex) {
        item.position = Offset(
          item.position.dx,
          item.position.dy - CanvasController.canvasH,
        );
      }
    }
    totalPages--;
    if (currentPage >= totalPages) currentPage = totalPages - 1;
  }

  // ─── 9. generateContent (async) ─────────────────────────────────────
  Future<bool> applyGenerateContent(
      GenerateContentOp op,
      Map<String, CanvasItem> lookup,
      List<Future<void>> pendingGenerations,
      ) async {
    final item = _resolveItem(op.itemId, lookup);
    _requireText(item);

    // Kick off the AI call in the background. UI awaits via OpResult.
    final future = _runGenerateContent(item, op);
    pendingGenerations.add(future);
    return true;
  }

  Future<void> _runGenerateContent(
      CanvasItem item,
      GenerateContentOp op,
      ) async {
    try {
      // Use aiRewrite for "rewrite" mode (operates on existing text),
      // aiFill for "replace" / "append" (generates fresh).
      final ctrl = item.controller!;
      final currentText = ctrl.document.toPlainText().trimRight();

      if (op.mode == GenerateMode.rewrite && currentText.isNotEmpty) {
        final rewritten = await ClaudeService.aiRewriteSection(
          text: currentText,
          sectionType: op.sectionType ?? item.sectionType.key,
          mode: 'professional',
          customInstruction: op.instruction,
        );
        if (rewritten != null && rewritten.isNotEmpty) {
          _writeTextIntoItem(item, rewritten, append: false);
        }
      } else {
        // For replace/append, use aiFill which returns structured JSON.
        // For now, fall back to aiRewrite with a synthesized prompt.
        // (A dedicated aiFill path for this is a future refinement.)
        final base = currentText.isNotEmpty
            ? currentText
            : 'Generate ${op.sectionType ?? item.sectionType.key} content.';
        final result = await ClaudeService.aiRewriteSection(
          text: base,
          sectionType: op.sectionType ?? item.sectionType.key,
          mode: 'professional',
          customInstruction: op.instruction,
        );
        if (result != null && result.isNotEmpty) {
          _writeTextIntoItem(item, result, append: op.mode == GenerateMode.append);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('🤖 generateContent failed: $e');
    }
  }

  /// Writes plain text into a text item's controller. If [append] is true,
  /// keeps existing content; otherwise replaces.
  void _writeTextIntoItem(CanvasItem item, String text, {required bool append}) {
    final ctrl = item.controller;
    if (ctrl == null) return;
    final out = text.endsWith('\n') ? text : '$text\n';
    if (append) {
      final currentLen = ctrl.document.length - 1; // exclude trailing \n
      ctrl.document.insert(currentLen, '\n$out');
    } else {
      ctrl.document = Document.fromDelta(Delta()..insert(out));
    }
  }

  // ─── 10. updateTable ────────────────────────────────────────────────
  Future<bool> applyUpdateTable(
      UpdateTableOp op,
      Map<String, CanvasItem> lookup,
      ) async {
    final item = _resolveItem(op.itemId, lookup);
    _requireTable(item);
    final td = item.tableData!;

    switch (op.action) {
      case TableAction.setCell:
        if (op.row == null || op.col == null) {
          throw OpFailureException(
              'invalidIndex', 'setCell needs row and col.');
        }
        // row 0 in op = header when showHeader is true.
        if (td.showHeader && op.row == 0) {
          td.setHeader(op.col!, op.value ?? '');
        } else {
          final dataRow = td.showHeader ? op.row! - 1 : op.row!;
          td.setCell(dataRow, op.col!, op.value ?? '');
        }
        break;

      case TableAction.setRow:
        if (op.row == null || op.rowValues == null) {
          throw OpFailureException(
              'invalidIndex', 'setRow needs row and rowValues.');
        }
        final dataRow = td.showHeader ? op.row! - 1 : op.row!;
        if (dataRow < 0 || dataRow >= td.rowCount) {
          throw OpFailureException(
              'invalidIndex', 'Row ${op.row} out of range.');
        }
        for (int c = 0; c < td.columnCount && c < op.rowValues!.length; c++) {
          td.setCell(dataRow, c, op.rowValues![c]);
        }
        break;

      case TableAction.setColumn:
        if (op.col == null || op.rowValues == null) {
          throw OpFailureException(
              'invalidIndex', 'setColumn needs col and rowValues.');
        }
        for (int r = 0; r < td.rowCount && r < op.rowValues!.length; r++) {
          td.setCell(r, op.col!, op.rowValues![r]);
        }
        break;

      case TableAction.addRow:
        td.addRow();
        if (op.rowValues != null) {
          final newRowIdx = td.rowCount - 1;
          for (int c = 0; c < td.columnCount && c < op.rowValues!.length; c++) {
            td.setCell(newRowIdx, c, op.rowValues![c]);
          }
        }
        break;

      case TableAction.addColumn:
        td.addColumn(op.value ?? '');
        break;

      case TableAction.deleteRow:
        if (op.row == null) {
          throw OpFailureException('invalidIndex', 'deleteRow needs row.');
        }
        final dataRow = td.showHeader ? op.row! - 1 : op.row!;
        td.removeRow(dataRow);
        break;

      case TableAction.deleteColumn:
        if (op.col == null) {
          throw OpFailureException('invalidIndex', 'deleteColumn needs col.');
        }
        td.removeColumn(op.col!);
        break;

      case TableAction.setHeaderStyle:
      case TableAction.setBorderStyle:
        final style = op.style;
        if (style == null) {
          throw OpFailureException(
              'invalidIndex', 'Style action needs a style map.');
        }
        if (style.containsKey('headerBgColor')) {
          final c = _parseColorOrNull(style['headerBgColor'] as String?);
          if (c != null) td.headerBgColor = c;
        }
        if (style.containsKey('headerTextColor')) {
          final c = _parseColorOrNull(style['headerTextColor'] as String?);
          if (c != null) td.headerTextColor = c;
        }
        if (style.containsKey('cellTextColor')) {
          final c = _parseColorOrNull(style['cellTextColor'] as String?);
          if (c != null) td.cellTextColor = c;
        }
        if (style.containsKey('borderColor')) {
          final c = _parseColorOrNull(style['borderColor'] as String?);
          if (c != null) td.borderColor = c;
        }
        if (style.containsKey('fontSize')) {
          final v = (style['fontSize'] as num?)?.toDouble();
          if (v != null) td.fontSize = v.clamp(6, 24);
        }
        if (style.containsKey('showHeader')) {
          final v = style['showHeader'];
          if (v is bool) td.showHeader = v;
        }
        break;

      case TableAction.unknown:
        throw OpFailureException(
            'invalidIndex', 'Unknown updateTable action.');
    }
    debugPrint('🤖 updateTable: ${op.action.name}');
    return true;
  }

  // ─── 11. updateReflow ───────────────────────────────────────────────
  Future<bool> applyUpdateReflow(
      UpdateReflowOp op,
      Map<String, CanvasItem> lookup,
      ) async {
    final item = _resolveItem(op.itemId, lookup);
    if (op.hasRole) item.role = op.role; // null = clear
    if (op.hasGroup) item.group = op.group;
    // beforeHeadingGap is reflow-engine knowledge; ignored here for now.
    debugPrint('🤖 updateReflow: ${item.id} role=${item.role} group=${item.group}');
    return true;
  }
}