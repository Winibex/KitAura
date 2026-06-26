// lib/shared/canvas/engine/canvas_template_io.dart
//
// Template I/O extracted from canvas_controller.dart during E1 file
// structure cleanup. This is a `part of` canvas_controller.dart — same
// library, full access to private members.
//
// What lives here:
//   - JSON ↔ CanvasItem serialization (buildItemFromMap, exportTemplateJson)
//   - Full template apply (applyTemplateJson, loadTemplate)
//   - Firestore document JSON (toFirestoreJson)
//   - AI snapshot building (buildSnapshot, _itemToSnapshotJson)
//   - Continuation management (_clearContinuations, _buildContinuations)
//   - Color hex converters (hexColor, colorToHex)
//
// What does NOT live here (stays on the main controller):
//   - autoArrange() — orchestrates reflow + continuations, but is a core
//     canvas operation triggered by users, not a template I/O concern.

part of 'canvas_controller.dart';

/// Strips inline attributes from \n ops.
/// flutter_quill asserts `after.isPlain` — newlines must NEVER carry
/// inline attrs (color, size, bold, font, italic).
///
/// Top-level function (was static method on CanvasController). Dart
/// extensions can't host static methods that get called via the class
/// name, but top-level functions in the same library work the same way.
List<dynamic> _sanitizeDelta(List<dynamic> ops) {
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

extension CanvasTemplateIO on CanvasController {

  // ─── COLOR CONVERTERS ─────────────────────────────────────────────────

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

  // ─── BUILD ITEM FROM JSON ─────────────────────────────────────────────

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

  // ─── FULL TEMPLATE APPLY / LOAD ───────────────────────────────────────

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

    clearContinuations();          // public extension method — see below
    autosizeAll();
    ReflowEngine.arrange(items, CanvasController.canvasH);
    buildContinuations();

    // Auto-calculate page count from item positions
    double maxY = 0;
    for (final item in items) {
      final bottom = item.position.dy + item.height;
      if (bottom > maxY) maxY = bottom;
    }

    totalPages = (maxY / CanvasController.canvasH).ceil().clamp(1, 99);
    currentPage = 0;

    canvasBackground = hexColor(bg);
    selectedId = null;
    multiSelected.clear();
    notifyFromExtension();
  }

  Future<void> loadTemplate(String assetPath) async {
    saveSnapshot();
    final jsonStr = await rootBundle.loadString(assetPath);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    applyTemplateJson(json);
  }

  // ─── EXPORT TEMPLATE JSON ─────────────────────────────────────────────

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
      if (item.role != null) map['role'] = item.role;
      if (item.group != null) map['group'] = item.group;
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
        if (item.role != null) map['role'] = item.role;
        if (item.group != null) map['group'] = item.group;
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

  // ─── AI SNAPSHOT BUILDER ──────────────────────────────────────────────

  Map<String, dynamic> buildSnapshot() {
    final realItems = items.where((i) => !i.isContinuation).toList();

    return {
      'pageCount': totalPages,
      'canvasBackground': colorToHex(canvasBackground),
      'items': [
        for (int idx = 0; idx < realItems.length; idx++)
          _itemToSnapshotJson(realItems[idx], 'i$idx'),
      ],
    };
  }

  Map<String, dynamic> _itemToSnapshotJson(CanvasItem item, String shortId) {
    final page = (item.position.dy / CanvasController.canvasH).floor() + 1; // 1-based for the AI
    final map = <String, dynamic>{
      'id': shortId,
      'page': page,
      'type': canvasItemTypeToString(item.type),
      'x': item.position.dx.round(),
      'y': item.position.dy.round(),
      'w': item.width.round(),
      'h': item.height.round(),
    };
    if (item.title.isNotEmpty) map['title'] = item.title;
    if (item.sectionType != SectionType.custom) {
      map['sectionType'] = item.sectionType.key;
    }
    if (item.role != null) map['role'] = item.role;
    if (item.group != null) map['group'] = item.group;

    // Shape items: include color so the AI can reference "the navy bar".
    if (!item.isText && !item.isTable) {
      map['color'] = colorToHex(item.color);
    }

    // Text items: include a line count so the AI can target a line index
    // without seeing the full text.
    if (item.isText && item.controller != null) {
      final plain = item.controller!.document.toPlainText();
      final lineCount = plain.split('\n').length - 1;
      map['lineCount'] = lineCount.clamp(0, 9999);
    }

    // Table items: include header count + row count.
    if (item.isTable && item.tableData != null) {
      map['columnCount'] = item.tableData!.columnCount;
      map['rowCount'] = item.tableData!.rowCount;
    }

    return map;
  }

  // ─── CONTINUATIONS ────────────────────────────────────────────────────
  //
  // Renamed from _clearContinuations / _buildContinuations to clearContinuations
  // / buildContinuations (no leading underscore) so they can be called from the
  // main controller's autoArrange() — extensions can't expose private members
  // back to their host class.

  /// Removes all continuation items. Must run BEFORE reflow so the engine
  /// never sees stale continuations as real content.
  void clearContinuations() {
    items.removeWhere((i) {
      if (i.isContinuation) { i.dispose(); return true; }
      return false;
    });
    // Clear overflow markers on real items so reflow starts clean.
    for (final i in items) {
      i.overflowSegments = null;
      i.displayOps = null;
      i.displayTableData = null;
      i.displayController?.dispose();
      i.displayController = null;
    }
  }

  /// After reflow, create one continuation item per overflow segment.
  /// Rebuilt every reflow, never saved (excluded via !isContinuation filter).
  void buildContinuations() {
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

    // Build read-only display controllers for split text parents.
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

    // Clone pinned items onto every body page (sidebars, stripes, decorations).
    final pinnedSources = items.where((i) => i.role == 'pinned' && !i.isContinuation).toList();
    if (pinnedSources.isNotEmpty) {
      double maxY = 0;
      for (final i in items) {
        final b = i.position.dy + i.height;
        if (b > maxY) maxY = b;
      }
      final pageCount = (maxY / CanvasController.canvasH).ceil().clamp(1, 99);

      final hasHero = items.any((i) => i.role == 'hero');
      final startPage = hasHero ? 1 : 0;

      for (final src in pinnedSources) {
        final srcPage = (src.position.dy / CanvasController.canvasH).floor();
        final intraY = src.position.dy - (srcPage * CanvasController.canvasH);

        for (int p = startPage; p < pageCount; p++) {
          if (p == srcPage) continue;
          final clone = CanvasItem(
            type: src.type,
            position: Offset(src.position.dx, p * CanvasController.canvasH + intraY),
            width: src.width,
            height: src.height,
            color: src.color,
            borderColor: src.borderColor,
            borderWidth: src.borderWidth,
            rotation: src.rotation,
            title: '',
            sectionType: src.sectionType,
          );
          clone.isContinuation = true;
          if (src.isText && src.controller != null) {
            try {
              clone.controller!.document = Document.fromJson(
                  _sanitizeDelta(src.controller!.document.toDelta().toJson()));
            } catch (_) {}
          }
          if (src.isTable && src.tableData != null) {
            clone.tableData = src.tableData!.copyWith();
          }
          if (src.imageBytes != null) {
            clone.imageBytes = Uint8List.fromList(src.imageBytes!);
          }
          items.add(clone);
        }
      }
    }
  }
}