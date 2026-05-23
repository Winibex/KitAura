import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/canvas_item.dart';
import '../../models/canvas_item_type.dart';
import '../../models/section_type.dart';

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

  static const Map<String, String> fontItems = {
    'Arial': 'Arial',
    'Open Sans': 'OpenSans',
    'Poppins': 'Poppins',
    'Sekuya': 'Sekuya',
  };


  // In canvas_controller.dart:
  Future<void> loadFromJson(Map<String, dynamic> json) async {
    applyTemplateJson(json);  // you already have this method
    notifyListeners();
  }

  // ─── PAGES ──────────────────────────────────────────────────────────────

  void addPage() {
    totalPages++;
    currentPage = totalPages - 1;
    // Clear selection when switching pages
    selectedId = null;
    multiSelected.clear();
    notifyListeners();
  }

  void removePage(int pageIndex) {
    if (totalPages <= 1) return;
    // Remove items on this page
    items.removeWhere((item) {
      final itemPage = _getItemPage(item);
      if (itemPage == pageIndex) {
        item.dispose();
        return true;
      }
      return false;
    });
    // Shift items on later pages up
    for (final item in items) {
      final itemPage = _getItemPage(item);
      if (itemPage > pageIndex) {
        item.position = Offset(
          item.position.dx,
          item.position.dy - canvasH,
        );
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

  int _getItemPage(CanvasItem item) {
    return (item.position.dy / canvasH).floor();
  }

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

  void notify() {
    notifyListeners();
  }

  // ─── UNDO / REDO ──────────────────────────────────────────────────────

  void saveSnapshot() {
    _undoStack.add(CanvasSnapshot(
      items.map(ItemSnapshot.from).toList(),
      selectedId,
      canvasBackground,
    ));
    _redoStack.clear();
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    notifyListeners(); // ADD THIS — refreshes canUndo on the app bar
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(CanvasSnapshot(
      items.map(ItemSnapshot.from).toList(),
      selectedId,
      canvasBackground,
    ));
    _restoreSnapshot(_undoStack.removeLast());
  }

  void redo() {
    if (_redoStack.isEmpty) return;
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

    items.removeWhere((item) {
      if (!snapById.containsKey(item.id)) {
        item.dispose();
        return true;
      }
      return false;
    });

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
    }

    for (final snap in snapshot.items) {
      if (!existingById.containsKey(snap.id) &&
          snap.type != CanvasItemType.textSection) {
        items.add(CanvasItem(
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
        ));
      }
    }

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
    Offset position = const Offset(40, 40),
    double width = 200,
    double height = 60,
  })
  {
    saveSnapshot();
    final item = CanvasItem(
      type: CanvasItemType.textSection,
      position: position,
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

  void multiMoveUpdate(Offset delta) {
    for (final id in multiSelected) {
      final item = items.where((i) => i.id == id).firstOrNull;
      if (item == null) continue;
      item.position = Offset(
        (item.position.dx + delta.dx).clamp(0, canvasW - item.width),
        (item.position.dy + delta.dy).clamp(0, canvasH - item.height),
      );
    }
  }

  void multiMoveEnd() {
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
      flipX: map['flipX'] as bool? ?? false,
      flipY: map['flipY'] as bool? ?? false,
      sectionType: map['sectionType'] != null
          ? SectionType.fromKey(map['sectionType'] as String)
          : null, // null → auto-detect from title in constructor
    );

    if (item.isText && map['delta'] != null) {
      try {
        item.controller!.document =
            Document.fromJson(map['delta'] as List<dynamic>);
      } catch (_) {}
    }

    return item;
  }

  void applyTemplateJson(Map<String, dynamic> json) {
    for (final item in items) {
      item.dispose();
    }
    items.clear();

    final bg = json['canvasBackground'] as String? ?? '#FFFFFF';
    final rawItems = json['items'] as List<dynamic>;
    for (final raw in rawItems) {
      items.add(buildItemFromMap(raw as Map<String, dynamic>));
    }

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
    final itemsList = items.map((item) {
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
      if (item.isText && item.controller != null) {
        map['delta'] = item.controller!.document.toDelta().toJson();
      }
      return map;
    }).toList();

    return {
      'canvasBackground': colorToHex(canvasBackground),
      'items': itemsList,
    };
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

  PdfColor toPdfColor(Color c) =>
      PdfColor(c.r, c.g, c.b, c.a);

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
          child: pw.SizedBox(
              width: item.width, height: item.height, child: content),
        ),
      );
    }

    switch (item.type) {
      case CanvasItemType.textSection:
        final spans = <pw.InlineSpan>[];
        for (final op in item.controller!.document.toDelta().toList()) {
          if (!op.isInsert) continue;
          final text = (op.data as String? ?? '').replaceAll('\n', ' ');
          if (text.trim().isEmpty) continue;
          final a = op.attributes;
          spans.add(pw.TextSpan(
            text: text,
            style: pw.TextStyle(
              font: getFont(a?['font'] as String? ?? globalFont),
              fontSize: globalFontSize,
              fontWeight: a?['bold'] == true
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
              fontStyle: a?['italic'] == true
                  ? pw.FontStyle.italic
                  : pw.FontStyle.normal,
            ),
          ));
        }
        content = pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(item.title.toUpperCase(),
                style: pw.TextStyle(
                    font: getFont('OpenSans'),
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey600)),
            pw.Divider(thickness: 0.5, color: PdfColors.grey400),
            pw.SizedBox(height: 2),
            if (spans.isNotEmpty)
              pw.RichText(
                text: pw.TextSpan(
                  children: spans,
                  style: pw.TextStyle(
                      font: getFont(globalFont), fontSize: globalFontSize),
                ),
              ),
          ],
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
            border: pw.Border.all(
                color: toPdfColor(item.borderColor), width: item.borderWidth),
          ),
        );
        break;
      case CanvasItemType.circle:
        content = pw.Container(
          decoration: pw.BoxDecoration(
            color: toPdfColor(item.color),
            shape: pw.BoxShape.circle,
            border: pw.Border.all(
                color: toPdfColor(item.borderColor), width: item.borderWidth),
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
      default:
        content = pw.SizedBox();
    }

    return pw.Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: pw.Transform.rotateBox(
        angle: item.rotation,
        child:
        pw.SizedBox(width: item.width, height: item.height, child: content),
      ),
    );
  }

  Future<Uint8List> buildPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Stack(children: items.map(itemToPdf).toList()),
    ));
    return doc.save();
  }

  // ─── KEYBOARD HANDLER ─────────────────────────────────────────────────

  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      undo();
      return true;
    }
    if (isCtrl &&
        (event.logicalKey == LogicalKeyboardKey.keyY ||
            (isShift && event.logicalKey == LogicalKeyboardKey.keyZ))) {
      redo();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final textFocused =
      items.any((i) => i.isText && (i.focusNode?.hasFocus ?? false));
      if (!textFocused &&
          (selectedId != null || multiSelected.isNotEmpty)) {
        saveSnapshot();
        deleteSelected();
        return true;
      }
    }
    return false;
  }

  // ─── Add to Firestore ─────────────────────────────────────────────────

  Map<String, dynamic> toFirestoreJson(String userId, String templateId) {
    return {
      'userId': userId,
      'title': 'Untitled CV',
      'canvasBackground': colorToHex(canvasBackground),
      'templateId': templateId,
      'status': 'draft',
      'isArchived': false,
      'exportCount': 0,
      'items': items.map((item) {
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
        if (item.isText && item.controller != null) {
          map['delta'] = item.controller!.document.toDelta().toJson();
        }
        return map;
      }).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  void updateSectionType(SectionType newType) {
    if (selected == null) return;
    saveSnapshot();
    selected!.sectionType = newType;
    notifyListeners();
  }
}