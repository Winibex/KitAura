// lib/test_canvas_page.dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────
enum CanvasItemType { textSection, line, rectangle, circle, imageBox, icon,
  triangle, star, arrow, diamond, hexagon, skewedRectangle
}

enum ResizeHandle { topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }

// ─────────────────────────────────────────────
// Snapshot
// ─────────────────────────────────────────────
class _ItemSnapshot {
  final String id;
  final CanvasItemType type;
  final Offset position;
  final double width, height, rotation, borderWidth;
  final Color color, borderColor;
  final IconData? iconData;
  final String title;
  final bool flipX, flipY;

  _ItemSnapshot({
    required this.id, required this.type, required this.position,
    required this.width, required this.height, required this.rotation,
    required this.borderWidth, required this.color, required this.borderColor,
    required this.iconData, required this.title,
    required this.flipX, required this.flipY,
  });

  factory _ItemSnapshot.from(CanvasItem item) => _ItemSnapshot(
    id: item.id, type: item.type, position: item.position,
    width: item.width, height: item.height, rotation: item.rotation,
    borderWidth: item.borderWidth, color: item.color, borderColor: item.borderColor,
    iconData: item.iconData, title: item.title,
    flipX: item.flipX, flipY: item.flipY,
  );
}

class _CanvasSnapshot {
  final List<_ItemSnapshot> items;
  final String? selectedId;
  _CanvasSnapshot(this.items, this.selectedId);
}

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────
class CanvasItem {
  final String id;
  CanvasItemType type;
  Offset position;
  double width, height, rotation, borderWidth;
  Color color, borderColor;
  Uint8List? imageBytes;
  IconData? iconData;
  String title;
  bool flipX, flipY;

  QuillController? controller;
  FocusNode? focusNode;
  ScrollController? scrollController;

  CanvasItem({
    required this.type, required this.position,
    required this.width, required this.height,
    this.rotation = 0, this.color = Colors.transparent,
    this.borderColor = Colors.grey, this.borderWidth = 1,
    this.imageBytes, this.iconData, this.title = '',
    this.flipX = false, this.flipY = false,
  }) : id = UniqueKey().toString() {
    if (type == CanvasItemType.textSection) {
      controller = QuillController.basic();
      focusNode = FocusNode();
      scrollController = ScrollController();
    }
  }

  bool get isText => type == CanvasItemType.textSection;

  void dispose() {
    controller?.dispose();
    focusNode?.dispose();
    scrollController?.dispose();
  }
}


List<Offset> _shapeVertices(CanvasItemType type) {
  switch (type) {
    case CanvasItemType.triangle:
      return [const Offset(0.5, 0), const Offset(1, 1), const Offset(0, 1)];

    case CanvasItemType.diamond:
      return [
        const Offset(0.5, 0), const Offset(1, 0.5),
        const Offset(0.5, 1), const Offset(0, 0.5),
      ];

    case CanvasItemType.hexagon:
      return List.generate(6, (i) {
        final angle = (math.pi / 3) * i - math.pi / 6;
        return Offset(0.5 + 0.5 * math.cos(angle), 0.5 + 0.5 * math.sin(angle));
      });

    case CanvasItemType.star:
      final pts = <Offset>[];
      for (int i = 0; i < 10; i++) {
        final angle = (math.pi / 5) * i - math.pi / 2;
        final r = i.isEven ? 0.5 : 0.22;
        pts.add(Offset(0.5 + r * math.cos(angle), 0.5 + r * math.sin(angle)));
      }
      return pts;

    case CanvasItemType.arrow:
      return [
        const Offset(0, 0.3), const Offset(0.6, 0.3), const Offset(0.6, 0),
        const Offset(1, 0.5),
        const Offset(0.6, 1), const Offset(0.6, 0.7), const Offset(0, 0.7),
      ];

    case CanvasItemType.skewedRectangle:
      return [
        const Offset(0.15, 0), const Offset(1, 0),
        const Offset(0.85, 1), const Offset(0, 1),
      ];

    default:
      return [];
  }
}


// ─────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────
class TestCanvasPage extends StatefulWidget {
  const TestCanvasPage({super.key});
  @override
  State<TestCanvasPage> createState() => _TestCanvasPageState();
}

class _TestCanvasPageState extends State<TestCanvasPage> {
  static const double canvasW = 595;
  static const double canvasH = 842;

  final List<CanvasItem> _items = [];
  String? _selectedId;
  final Set<String> _multiSelected = {};

  Offset? _marqueeStart, _marqueeEnd;
  bool _isMarqueeActive = false;

  Key _toolbarKey = UniqueKey();
  String _globalFont = 'OpenSans';
  double _globalFontSize = 12;

  static const Map<String, String> _fontItems = {
    'Arial': 'Arial', 'Open Sans': 'OpenSans',
    'Poppins': 'Poppins', 'Sekuya': 'Sekuya',
  };

  final List<_CanvasSnapshot> _undoStack = [];
  final List<_CanvasSnapshot> _redoStack = [];
  final Map<String, pw.Font> _pdfFonts = {};
  bool _fontsLoaded = false;
  final FocusNode _keyboardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _addTextSection(title: 'Personal Info', position: const Offset(20, 20), width: 555, height: 60);
    _addTextSection(title: 'Summary', position: const Offset(20, 100), width: 555, height: 60);
    _addTextSection(title: 'Experience', position: const Offset(20, 180), width: 340, height: 60);
    _addTextSection(title: 'Skills', position: const Offset(375, 180), width: 200, height: 60);
    _preloadFonts();
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    for (final item in _items) item.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrl && !isShift && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _undo(); return true;
    }
    if (isCtrl && (event.logicalKey == LogicalKeyboardKey.keyY ||
        (isShift && event.logicalKey == LogicalKeyboardKey.keyZ))) {
      _redo(); return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final textFocused = _items.any((i) => i.isText && (i.focusNode?.hasFocus ?? false));
      if (!textFocused && (_selectedId != null || _multiSelected.isNotEmpty)) {
        _saveSnapshot(); _deleteSelected(); return true;
      }
    }
    return false;
  }

  // ── Undo/redo ────────────────────────────────

  void _saveSnapshot() {
    _undoStack.add(_CanvasSnapshot(_items.map(_ItemSnapshot.from).toList(), _selectedId));
    _redoStack.clear();
    if (_undoStack.length > 50) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_CanvasSnapshot(_items.map(_ItemSnapshot.from).toList(), _selectedId));
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_CanvasSnapshot(_items.map(_ItemSnapshot.from).toList(), _selectedId));
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _restoreSnapshot(_CanvasSnapshot snapshot) {
    final existingById = {for (final i in _items) i.id: i};
    final snapById = {for (final s in snapshot.items) s.id: s};

    _items.removeWhere((item) {
      if (!snapById.containsKey(item.id)) { item.dispose(); return true; }
      return false;
    });

    for (final item in _items) {
      final snap = snapById[item.id]!;
      item.type = snap.type; item.position = snap.position;
      item.width = snap.width; item.height = snap.height;
      item.rotation = snap.rotation; item.color = snap.color;
      item.borderColor = snap.borderColor; item.borderWidth = snap.borderWidth;
      item.iconData = snap.iconData; item.title = snap.title;
      item.flipX = snap.flipX; item.flipY = snap.flipY;
    }

    for (final snap in snapshot.items) {
      if (!existingById.containsKey(snap.id) && snap.type != CanvasItemType.textSection) {
        _items.add(CanvasItem(
          type: snap.type, position: snap.position,
          width: snap.width, height: snap.height,
          rotation: snap.rotation, color: snap.color,
          borderColor: snap.borderColor, borderWidth: snap.borderWidth,
          iconData: snap.iconData, title: snap.title,
          flipX: snap.flipX, flipY: snap.flipY,
        ));
      }
    }

    final order = snapshot.items.map((s) => s.id).toList();
    _items.sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));

    setState(() { _selectedId = snapshot.selectedId; _multiSelected.clear(); _toolbarKey = UniqueKey(); });
  }

  // ── Item management ──────────────────────────

  void _addTextSection({
    String title = 'New Section',
    Offset position = const Offset(40, 40),
    double width = 200, double height = 60,
  }) {
    _saveSnapshot();
    final item = CanvasItem(
      type: CanvasItemType.textSection, position: position,
      width: width, height: height, title: title,
      color: Colors.white, borderColor: Colors.grey.shade300,
    );
    item.focusNode!.addListener(() {
      if (item.focusNode!.hasFocus && _selectedId != item.id) {
        setState(() { _selectedId = item.id; _multiSelected.clear(); _toolbarKey = UniqueKey(); });
      }
    });
    setState(() { _items.add(item); _selectedId = item.id; _multiSelected.clear(); _toolbarKey = UniqueKey(); });
  }

  void _addShape(CanvasItemType type) {
    _saveSnapshot();
    final defaults = <CanvasItemType, Map<String, dynamic>>{
      CanvasItemType.line:      {'w': 200.0, 'h': 4.0,   'color': Colors.transparent, 'border': Colors.black},
      CanvasItemType.rectangle: {'w': 160.0, 'h': 100.0, 'color': Colors.blue.shade50, 'border': Colors.blue},
      CanvasItemType.circle:    {'w': 100.0, 'h': 100.0, 'color': Colors.green.shade50,'border': Colors.green},
      CanvasItemType.imageBox:  {'w': 160.0, 'h': 120.0, 'color': Colors.grey.shade100,'border': Colors.grey},
      CanvasItemType.icon:      {'w': 48.0,  'h': 48.0,  'color': Colors.transparent,  'border': Colors.blue},
      CanvasItemType.triangle:         {'w': 120.0, 'h': 120.0, 'color': Colors.orange.shade50, 'border': Colors.orange},
      CanvasItemType.star:             {'w': 120.0, 'h': 120.0, 'color': Colors.yellow.shade50, 'border': Colors.orange},
      CanvasItemType.arrow:            {'w': 160.0, 'h': 80.0,  'color': Colors.teal.shade50,   'border': Colors.teal},
      CanvasItemType.diamond:          {'w': 100.0, 'h': 120.0, 'color': Colors.pink.shade50,   'border': Colors.pink},
      CanvasItemType.hexagon:          {'w': 120.0, 'h': 120.0, 'color': Colors.purple.shade50, 'border': Colors.purple},
      CanvasItemType.skewedRectangle:  {'w': 160.0, 'h': 80.0,  'color': Colors.indigo.shade50, 'border': Colors.indigo},
    };
    final d = defaults[type]!;
    final item = CanvasItem(
      type: type, position: const Offset(100, 100),
      width: d['w'] as double, height: d['h'] as double,
      color: d['color'] as Color, borderColor: d['border'] as Color,
      iconData: type == CanvasItemType.icon ? Icons.star : null,
    );
    setState(() { _items.add(item); _selectedId = item.id; _multiSelected.clear(); });
  }

  void _deleteSelected() {
    final toDelete = _multiSelected.isNotEmpty
        ? Set<String>.from(_multiSelected)
        : (_selectedId != null ? {_selectedId!} : <String>{});
    for (final id in toDelete) {
      final idx = _items.indexWhere((i) => i.id == id);
      if (idx != -1) { _items[idx].dispose(); _items.removeAt(idx); }
    }
    setState(() { _selectedId = null; _multiSelected.clear(); _toolbarKey = UniqueKey(); });
  }

  CanvasItem? get _selected =>
      _selectedId == null ? null : _items.where((i) => i.id == _selectedId).firstOrNull;

  // ── Z-order ──────────────────────────────────

  void _bringToFront() {
    final id = _selectedId; if (id == null) return;
    _saveSnapshot();
    final idx = _items.indexWhere((i) => i.id == id);
    setState(() { final item = _items.removeAt(idx); _items.add(item); });
  }

  void _sendToBack() {
    final id = _selectedId; if (id == null) return;
    _saveSnapshot();
    final idx = _items.indexWhere((i) => i.id == id);
    setState(() { final item = _items.removeAt(idx); _items.insert(0, item); });
  }

  void _bringForward() {
    final id = _selectedId; if (id == null) return;
    _saveSnapshot();
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx < _items.length - 1) setState(() { final item = _items.removeAt(idx); _items.insert(idx + 1, item); });
  }

  void _sendBackward() {
    final id = _selectedId; if (id == null) return;
    _saveSnapshot();
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx > 0) setState(() { final item = _items.removeAt(idx); _items.insert(idx - 1, item); });
  }

  // ── Marquee ───────────────────────────────────

  void _onMarqueeEnd() {
    if (_marqueeStart == null || _marqueeEnd == null) {
      setState(() { _isMarqueeActive = false; _marqueeStart = null; _marqueeEnd = null; });
      return;
    }
    final rect = Rect.fromPoints(_marqueeStart!, _marqueeEnd!);
    final selected = <String>{};
    for (final item in _items) {
      if (rect.overlaps(Rect.fromLTWH(item.position.dx, item.position.dy, item.width, item.height))) {
        selected.add(item.id);
      }
    }
    setState(() {
      _multiSelected.clear(); _multiSelected.addAll(selected);
      _selectedId = selected.length == 1 ? selected.first : null;
      _isMarqueeActive = false; _marqueeStart = null; _marqueeEnd = null;
      if (selected.length == 1) _toolbarKey = UniqueKey();
    });
  }

  void _onMultiMoveUpdate(Offset delta) {
    setState(() {
      for (final id in _multiSelected) {
        final item = _items.where((i) => i.id == id).firstOrNull;
        if (item == null) continue;
        item.position = Offset(
          (item.position.dx + delta.dx).clamp(0, canvasW - item.width),
          (item.position.dy + delta.dy).clamp(0, canvasH - item.height),
        );
      }
    });
  }

  // ── Color / image / icon ──────────────────────

  void _showColorPicker({required bool isBorder}) {
    final item = _selected; if (item == null) return;
    Color current = isBorder ? item.borderColor : item.color;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBorder ? 'Border / Line Color' : 'Fill Color'),
        content: SingleChildScrollView(
          child: ColorPicker(pickerColor: current, onColorChanged: (c) => current = c,
              enableAlpha: true, labelTypes: const []),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () {
            _saveSnapshot();
            setState(() { if (isBorder) item.borderColor = current; else item.color = current; });
            Navigator.pop(ctx);
          }, child: const Text('Apply')),
        ],
      ),
    );
  }

  Future<void> _uploadImage(CanvasItem item) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result?.files.single.bytes != null) {
      _saveSnapshot();
      setState(() => item.imageBytes = result!.files.single.bytes);
    }
  }

  void _showIconPicker(CanvasItem item) {
    final icons = <IconData>[
      Icons.star, Icons.favorite, Icons.phone, Icons.email, Icons.location_on,
      Icons.work, Icons.school, Icons.person, Icons.link, Icons.language,
      Icons.code, Icons.build, Icons.check_circle, Icons.arrow_forward,
      Icons.lightbulb, Icons.emoji_events, Icons.bar_chart, Icons.calendar_today,
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick an Icon'),
        content: Wrap(spacing: 12, runSpacing: 12,
          children: icons.map((ic) => GestureDetector(
            onTap: () { _saveSnapshot(); setState(() => item.iconData = ic); Navigator.pop(ctx); },
            child: Icon(ic, size: 32, color: item.borderColor),
          )).toList(),
        ),
      ),
    );
  }

  // ── Global styles ─────────────────────────────

  void _applyGlobalFont(String family) {
    _saveSnapshot();
    setState(() => _globalFont = family);
    for (final item in _items) {
      if (!item.isText) continue;
      final len = item.controller!.document.length;
      if (len <= 1) continue;
      item.controller!.formatText(0, len - 1, Attribute.fromKeyValue('font', family));
    }
  }

  void _applyGlobalFontSize(double size) {
    _saveSnapshot();
    setState(() => _globalFontSize = size);
    for (final item in _items) {
      if (!item.isText) continue;
      final len = item.controller!.document.length;
      if (len <= 1) continue;
      item.controller!.formatText(0, len - 1, Attribute.fromKeyValue('size', '${size.toInt()}pt'));
    }
  }

  // ── PDF ───────────────────────────────────────

  Future<void> _preloadFonts() async {
    try {
      Future<pw.Font> load(String p) async => pw.Font.ttf(await rootBundle.load(p));
      _pdfFonts['Arial']    = await load('assets/fonts/Arial.ttf');
      _pdfFonts['OpenSans'] = await load('assets/fonts/OpenSans.ttf');
      _pdfFonts['Poppins']  = await load('assets/fonts/Poppins.ttf');
      _pdfFonts['Sekuya']   = await load('assets/fonts/Sekuya.ttf');
      if (mounted) setState(() => _fontsLoaded = true);
    } catch (e) { debugPrint('Font load error: $e'); }
  }

  pw.Font _getFont(String? f) => _pdfFonts[f] ?? _pdfFonts['OpenSans'] ?? _pdfFonts.values.first;
  PdfColor _toPdf(Color c) => PdfColor(c.red / 255, c.green / 255, c.blue / 255, c.alpha / 255);

  pw.Widget _itemToPdf(CanvasItem item) {
    pw.Widget content;

    // Polygon-based shapes
    final vertices = _shapeVertices(item.type);
    if (vertices.isNotEmpty) {
      content = pw.CustomPaint(
        size: PdfPoint(item.width, item.height),
        painter: (PdfGraphics canvas, PdfPoint size) {
          if (vertices.isEmpty) return;
          final pts = vertices.map((v) =>
              PdfPoint(v.dx * size.x, v.dy * size.y)).toList();
          canvas.moveTo(pts.first.x, pts.first.y);
          for (final pt in pts.skip(1)) canvas.lineTo(pt.x, pt.y);
          canvas.closePath();
          canvas.setFillColor(_toPdf(item.color));
          canvas.setStrokeColor(_toPdf(item.borderColor));
          canvas.setLineWidth(item.borderWidth);
          canvas.fillAndStrokePath();
        },
      );
      return pw.Positioned(
        left: item.position.dx, top: item.position.dy,
        child: pw.Transform.rotateBox(angle: item.rotation,
            child: pw.SizedBox(width: item.width, height: item.height, child: content)),
      );
    }

    // Primitive shapes
    switch (item.type) {
      case CanvasItemType.textSection:
        final spans = <pw.InlineSpan>[];
        for (final op in item.controller!.document.toDelta().toList()) {
          if (!op.isInsert) continue;
          final text = (op.data as String? ?? '').replaceAll('\n', ' ');
          if (text.trim().isEmpty) continue;
          final a = op.attributes;
          spans.add(pw.TextSpan(text: text, style: pw.TextStyle(
            font: _getFont(a?['font'] as String? ?? _globalFont),
            fontSize: _globalFontSize,
            fontWeight: a?['bold'] == true ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontStyle: a?['italic'] == true ? pw.FontStyle.italic : pw.FontStyle.normal,
          )));
        }
        content = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(item.title.toUpperCase(), style: pw.TextStyle(
              font: _getFont('OpenSans'), fontSize: 8,
              fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
          pw.Divider(thickness: 0.5, color: PdfColors.grey400),
          pw.SizedBox(height: 2),
          if (spans.isNotEmpty) pw.RichText(text: pw.TextSpan(
              children: spans,
              style: pw.TextStyle(font: _getFont(_globalFont), fontSize: _globalFontSize))),
        ]);
        break;
      case CanvasItemType.line:
        content = pw.Container(width: item.width,
            height: item.borderWidth.clamp(1, 12), color: _toPdf(item.borderColor));
        break;
      case CanvasItemType.rectangle:
        content = pw.Container(decoration: pw.BoxDecoration(
            color: _toPdf(item.color),
            border: pw.Border.all(color: _toPdf(item.borderColor), width: item.borderWidth)));
        break;
      case CanvasItemType.circle:
        content = pw.Container(decoration: pw.BoxDecoration(
            color: _toPdf(item.color), shape: pw.BoxShape.circle,
            border: pw.Border.all(color: _toPdf(item.borderColor), width: item.borderWidth)));
        break;
      case CanvasItemType.imageBox:
        content = item.imageBytes != null
            ? pw.Image(pw.MemoryImage(item.imageBytes!), fit: pw.BoxFit.cover)
            : pw.Container(decoration: pw.BoxDecoration(
            color: _toPdf(item.color),
            border: pw.Border.all(color: _toPdf(item.borderColor))));
        break;
      case CanvasItemType.icon:
        content = pw.Container(decoration: pw.BoxDecoration(
            color: _toPdf(item.borderColor), shape: pw.BoxShape.circle));
        break;
      default:
        content = pw.SizedBox();
    }

    return pw.Positioned(
      left: item.position.dx, top: item.position.dy,
      child: pw.Transform.rotateBox(angle: item.rotation,
          child: pw.SizedBox(width: item.width, height: item.height, child: content)),
    );
  }

  Future<Uint8List> _buildPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4, margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Stack(children: _items.map(_itemToPdf).toList()),
    ));
    return doc.save();
  }

  Future<void> _exportPdf() async {
    if (!_fontsLoaded) return;
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: 'kitaura_cv.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF error: $e')));
    }
  }

  // ── Build ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final isMulti = _multiSelected.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 3: Free Canvas CV'),
        actions: [
          IconButton(icon: const Icon(Icons.undo), tooltip: 'Undo (Ctrl+Z)',
              onPressed: _undoStack.isNotEmpty ? _undo : null),
          IconButton(icon: const Icon(Icons.redo), tooltip: 'Redo (Ctrl+Y)',
              onPressed: _redoStack.isNotEmpty ? _redo : null),
          IconButton(icon: const Icon(Icons.picture_as_pdf),
              onPressed: _fontsLoaded ? _exportPdf : null),
        ],
      ),
      body: Row(children: [

        // ── LEFT PANEL ──────────────────────────
        Container(
          width: 260, color: Colors.grey.shade100,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Quill toolbar
              if (selected?.isText == true)
                Container(color: Colors.white,
                  child: QuillSimpleToolbar(
                    key: _toolbarKey, controller: selected!.controller!,
                    config: QuillSimpleToolbarConfig(toolbarSize: 36,
                        buttonOptions: QuillSimpleToolbarButtonOptions(
                            fontFamily: QuillToolbarFontFamilyButtonOptions(items: _fontItems))),
                  ),
                ),

              const Divider(height: 1),

              // Add elements
              _panelHeader('Add Elements'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  _addBtn('Text',    Icons.text_fields,            () => _addTextSection()),
                  _addBtn('Line',    Icons.horizontal_rule,        () => _addShape(CanvasItemType.line)),
                  _addBtn('Rect',    Icons.rectangle_outlined,     () => _addShape(CanvasItemType.rectangle)),
                  _addBtn('Circle',  Icons.circle_outlined,        () => _addShape(CanvasItemType.circle)),
                  _addBtn('Image',   Icons.image_outlined,         () => _addShape(CanvasItemType.imageBox)),
                  _addBtn('Icon',    Icons.emoji_emotions_outlined, () => _addShape(CanvasItemType.icon)),
                  _addBtn('Triangle',Icons.change_history,         () => _addShape(CanvasItemType.triangle)),
                  _addBtn('Star',    Icons.star_outline,           () => _addShape(CanvasItemType.star)),
                  _addBtn('Arrow',   Icons.arrow_forward,          () => _addShape(CanvasItemType.arrow)),
                  _addBtn('Diamond', Icons.diamond_outlined,       () => _addShape(CanvasItemType.diamond)),
                  _addBtn('Hexagon', Icons.hexagon_outlined,       () => _addShape(CanvasItemType.hexagon)),
                  _addBtn('Skewed',  Icons.rectangle_outlined,     () => _addShape(CanvasItemType.skewedRectangle)),
                ]),
              ),

              const Divider(height: 1),

              // Properties
              if (selected != null || isMulti) ...[
                _panelHeader(isMulti
                    ? 'Multi-select (${_multiSelected.length})'
                    : 'Properties  •  ${selected!.title.isNotEmpty ? selected.title : selected.type.name}'),

                // Delete button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: SizedBox(width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () { _saveSnapshot(); _deleteSelected(); },
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                      label: const Text('Delete  (Del)', style: TextStyle(color: Colors.red, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 6)),
                    ),
                  ),
                ),

                // Layers
                if (!isMulti && selected != null) ...[
                  _panelHeader('Layers'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(children: [
                      _layerBtn(Icons.flip_to_front, 'Front', _bringToFront),
                      const SizedBox(width: 4),
                      _layerBtn(Icons.arrow_upward, 'Forward', _bringForward),
                      const SizedBox(width: 4),
                      _layerBtn(Icons.arrow_downward, 'Backward', _sendBackward),
                      const SizedBox(width: 4),
                      _layerBtn(Icons.flip_to_back, 'Back', _sendToBack),
                    ]),
                  ),
                ],

                // Flip — only for non-text, single select
                if (!isMulti && selected != null && !selected.isText) ...[
                  _panelHeader('Flip'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () { _saveSnapshot(); setState(() => selected.flipX = !selected.flipX); },
                        icon: const Icon(Icons.flip, size: 14),
                        label: const Text('Horizontal', style: TextStyle(fontSize: 11)),
                      )),
                      const SizedBox(width: 4),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () { _saveSnapshot(); setState(() => selected.flipY = !selected.flipY); },
                        icon: const Icon(Icons.flip, size: 14),
                        label: const Text('Vertical', style: TextStyle(fontSize: 11)),
                      )),
                    ]),
                  ),
                ],

                // Fill color
                if (!isMulti && selected != null &&
                    selected.type != CanvasItemType.line &&
                    selected.type != CanvasItemType.icon &&
                    selected.type != CanvasItemType.textSection)
                  _colorRow('Fill Color', selected.color, () => _showColorPicker(isBorder: false)),

                // Border / line color
                if (!isMulti && selected != null && !selected.isText)
                  _colorRow(
                    selected.type == CanvasItemType.line ? 'Line Color' : 'Border Color',
                    selected.borderColor, () => _showColorPicker(isBorder: true),
                  ),

                // AFTER — covers all shapes that have a border
                if (!isMulti && selected != null &&
                    !selected.isText &&
                    selected.type != CanvasItemType.imageBox &&
                    selected.type != CanvasItemType.icon)
                  _sliderRow(
                    selected.type == CanvasItemType.line ? 'Thickness' : 'Border Width',
                    selected.borderWidth, 1, 12,
                        (v) => setState(() => selected.borderWidth = v),
                  ),

                // Rotation with angle number display
                if (!isMulti && selected != null && !selected.isText) ...[
                  _panelHeader('Rotation'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      const Text('Angle', style: TextStyle(fontSize: 12)),
                      Expanded(child: Slider(
                        value: (selected.rotation * (180 / math.pi)) % 360,
                        min: 0, max: 360,
                        onChanged: (v) => setState(() => selected.rotation = v * (math.pi / 180)),
                        onChangeEnd: (_) => _saveSnapshot(),
                      )),
                      Container(
                        width: 40, alignment: Alignment.center,
                        child: Text(
                          '${((selected.rotation * (180 / math.pi)) % 360).toStringAsFixed(0)}°',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w600, color: Colors.blue),
                        ),
                      ),
                    ]),
                  ),
                ],

                // Image upload
                if (!isMulti && selected?.type == CanvasItemType.imageBox)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SizedBox(width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _uploadImage(selected!),
                        icon: const Icon(Icons.upload, size: 14),
                        label: const Text('Upload Image', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),

                // Icon picker + color
                if (!isMulti && selected?.type == CanvasItemType.icon) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SizedBox(width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showIconPicker(selected!),
                        icon: const Icon(Icons.emoji_emotions_outlined, size: 14),
                        label: const Text('Change Icon', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                  _colorRow('Icon Color', selected!.borderColor,
                          () => _showColorPicker(isBorder: true)),
                ],
              ],

              const Divider(height: 1),

              // Global text styles
              if (_items.any((i) => i.isText)) ...[
                _panelHeader('Global Text Styles'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Column(children: [
                    Row(children: [
                      const Text('Font', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      Expanded(child: DropdownButton<String>(
                        value: _globalFont, isExpanded: true, isDense: true,
                        items: _fontItems.entries.map((e) => DropdownMenuItem(
                            value: e.value,
                            child: Text(e.key, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) { if (v != null) _applyGlobalFont(v); },
                      )),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Text('Size', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      DropdownButton<double>(
                        value: _globalFontSize, isDense: true,
                        items: [10,11,12,13,14,16,18,20,24].map((s) => DropdownMenuItem(
                            value: s.toDouble(),
                            child: Text('$s', style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) { if (v != null) _applyGlobalFontSize(v); },
                      ),
                    ]),
                  ]),
                ),
              ],

              // All layers list
              _panelHeader('All Layers'),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: _items.length,
                onReorder: (oldIdx, newIdx) {
                  if (newIdx > oldIdx) newIdx--;
                  _saveSnapshot();
                  setState(() { final item = _items.removeAt(oldIdx); _items.insert(newIdx, item); });
                },
                itemBuilder: (ctx, idx) {
                  final item = _items[_items.length - 1 - idx];
                  final isSel = item.id == _selectedId || _multiSelected.contains(item.id);
                  return ListTile(
                    key: ValueKey(item.id), dense: true,
                    selected: isSel, selectedTileColor: Colors.blue.shade50,
                    leading: Icon(_typeIcon(item.type), size: 14,
                        color: isSel ? Colors.blue : Colors.grey),
                    title: Text(item.title.isNotEmpty ? item.title : item.type.name,
                        style: TextStyle(fontSize: 12,
                            fontWeight: isSel ? FontWeight.w600 : FontWeight.normal)),
                    onTap: () => setState(() {
                      _selectedId = item.id; _multiSelected.clear();
                      if (item.isText) _toolbarKey = UniqueKey();
                    }),
                  );
                },
              ),
            ]),
          ),
        ),

        // ── RIGHT PANEL ───────────────────────────
        Expanded(
          child: Container(
            color: Colors.grey.shade400,
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: SizedBox(
                      width: canvasW, height: canvasH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // A4 white background + marquee gestures
                          Positioned.fill(
                            child: GestureDetector(
                              onTapDown: (_) => setState(() {
                                _selectedId = null; _multiSelected.clear();
                              }),
                              onPanStart: (d) => setState(() {
                                _isMarqueeActive = true;
                                _marqueeStart = d.localPosition;
                                _marqueeEnd = d.localPosition;
                              }),
                              onPanUpdate: (d) {
                                if (_isMarqueeActive) setState(() => _marqueeEnd = d.localPosition);
                              },
                              onPanEnd: (_) { if (_isMarqueeActive) _onMarqueeEnd(); },
                              child: Container(decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 16, offset: const Offset(0, 4))],
                              )),
                            ),
                          ),

                          // Canvas items
                          ..._items.map((item) => _CanvasItemWidget(
                            key: ValueKey(item.id),
                            item: item,
                            isSelected: item.id == _selectedId,
                            isMultiSelected: _multiSelected.contains(item.id),
                            canvasW: canvasW, canvasH: canvasH,
                            onSelect: () => setState(() {
                              _selectedId = item.id; _multiSelected.clear();
                              if (item.isText) _toolbarKey = UniqueKey();
                            }),
                            onMultiMoveUpdate: _multiSelected.contains(item.id)
                                ? _onMultiMoveUpdate : null,
                            onSaveSnapshot: _saveSnapshot,
                            fontItems: _fontItems,
                            toolbarKey: _toolbarKey,
                          )),

                          // Marquee overlay
                          if (_isMarqueeActive && _marqueeStart != null && _marqueeEnd != null)
                            Positioned.fill(child: IgnorePointer(
                              child: CustomPaint(
                                  painter: _MarqueePainter(_marqueeStart!, _marqueeEnd!)),
                            )),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Panel helpers ─────────────────────────────

  Widget _panelHeader(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
    child: Text(t, style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54)),
  );

  Widget _addBtn(String label, IconData icon, VoidCallback onTap) =>
      GestureDetector(onTap: onTap,
        child: Container(width: 72, padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey.shade300)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: Colors.blue),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10)),
          ]),
        ),
      );

  Widget _layerBtn(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(message: tooltip,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(4),
          child: Container(padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300)),
              child: Icon(icon, size: 14, color: Colors.blue.shade700)),
        ),
      );

  Widget _colorRow(String label, Color color, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 12)), const Spacer(),
      GestureDetector(onTap: onTap,
          child: Container(width: 28, height: 20,
              decoration: BoxDecoration(color: color,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(3)))),
    ]),
  );

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChange) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max,
              label: value.toStringAsFixed(0), onChanged: onChange)),
        ]),
      );

  IconData _typeIcon(CanvasItemType t) {
    switch (t) {
      case CanvasItemType.textSection:      return Icons.text_fields;
      case CanvasItemType.line:             return Icons.horizontal_rule;
      case CanvasItemType.rectangle:        return Icons.rectangle_outlined;
      case CanvasItemType.circle:           return Icons.circle_outlined;
      case CanvasItemType.imageBox:         return Icons.image_outlined;
      case CanvasItemType.icon:             return Icons.emoji_emotions_outlined;
      case CanvasItemType.triangle:         return Icons.change_history;
      case CanvasItemType.star:             return Icons.star_outline;
      case CanvasItemType.arrow:            return Icons.arrow_forward;
      case CanvasItemType.diamond:          return Icons.diamond_outlined;
      case CanvasItemType.hexagon:          return Icons.hexagon_outlined;
      case CanvasItemType.skewedRectangle:  return Icons.rectangle_outlined;
    }
  }
}

// ─────────────────────────────────────────────
// Marquee painter
// ─────────────────────────────────────────────
class _MarqueePainter extends CustomPainter {
  final Offset start, end;
  _MarqueePainter(this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(rect,
        Paint()..color = Colors.blue.withOpacity(0.1)..style = PaintingStyle.fill);
    canvas.drawRect(rect,
        Paint()..color = Colors.blue..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_MarqueePainter old) => old.start != start || old.end != end;
}

// ─────────────────────────────────────────────
// Canvas Item Widget
// ─────────────────────────────────────────────
class _CanvasItemWidget extends StatefulWidget {
  final CanvasItem item;
  final bool isSelected, isMultiSelected;
  final double canvasW, canvasH;
  final VoidCallback onSelect;
  final void Function(Offset delta)? onMultiMoveUpdate;
  final VoidCallback onSaveSnapshot;
  final Map<String, String> fontItems;
  final Key toolbarKey;

  const _CanvasItemWidget({
    super.key, required this.item, required this.isSelected,
    required this.isMultiSelected, required this.canvasW, required this.canvasH,
    required this.onSelect, required this.onSaveSnapshot,
    required this.fontItems, required this.toolbarKey,
    this.onMultiMoveUpdate,
  });

  @override
  State<_CanvasItemWidget> createState() => _CanvasItemWidgetState();
}

class _CanvasItemWidgetState extends State<_CanvasItemWidget> {
  late Offset _pos;
  late double _w, _h;
  Offset _dragStart = Offset.zero, _posAtDragStart = Offset.zero;
  double _wAtResize = 0, _hAtResize = 0;
  Offset _resizeOrigin = Offset.zero;
  ResizeHandle? _activeHandle;

  @override
  void initState() {
    super.initState();
    _pos = widget.item.position;
    _w   = widget.item.width;
    _h   = widget.item.height;
  }

  @override
  void didUpdateWidget(_CanvasItemWidget old) {
    super.didUpdateWidget(old);
    if (widget.item.position != _pos) _pos = widget.item.position;
    _w = widget.item.width;
    _h = widget.item.height;
  }

  void _commit() {
    widget.item.position = _pos;
    widget.item.width    = _w;
    widget.item.height   = _h;
  }

  void _onResizeUpdate(ResizeHandle handle, Offset delta) {
    double l = _posAtDragStart.dx, t = _posAtDragStart.dy;
    double r = l + _wAtResize, b = t + _hAtResize;
    final dx = delta.dx, dy = delta.dy;
    switch (handle) {
      case ResizeHandle.topLeft:     l += dx; t += dy; break;
      case ResizeHandle.top:         t += dy; break;
      case ResizeHandle.topRight:    r += dx; t += dy; break;
      case ResizeHandle.right:       r += dx; break;
      case ResizeHandle.bottomRight: r += dx; b += dy; break;
      case ResizeHandle.bottom:      b += dy; break;
      case ResizeHandle.bottomLeft:  l += dx; b += dy; break;
      case ResizeHandle.left:        l += dx; break;
    }
    const minW = 40.0, minH = 20.0;
    if (r - l < minW) { if (handle.name.contains('Left')) l = r - minW; else r = l + minW; }
    if (b - t < minH) { if (handle.name.contains('top'))  t = b - minH; else b = t + minH; }
    setState(() {
      _pos = Offset(l.clamp(0, widget.canvasW - minW), t.clamp(0, widget.canvasH - minH));
      _w = (r - l).clamp(minW, widget.canvasW - _pos.dx);
      _h = (b - t).clamp(minH, widget.canvasH - _pos.dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx, top: _pos.dy, width: _w, height: _h,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(widget.item.rotation)
          ..scale(
            widget.item.flipX ? -1.0 : 1.0,
            widget.item.flipY ? -1.0 : 1.0,
          ),
        child: Stack(clipBehavior: Clip.none, children: [
          GestureDetector(onTapDown: (_) => widget.onSelect(), child: _buildBody()),
          if (widget.isSelected || widget.isMultiSelected)
            Positioned.fill(child: IgnorePointer(
              child: Container(decoration: BoxDecoration(border: Border.all(
                  color: widget.isMultiSelected ? Colors.orange : Colors.blue,
                  width: 1.5))),
            )),
          if (widget.isSelected) ..._buildResizeHandles(),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.item.isText) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Drag handle with move cursor
        MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            onPanStart: (d) {
              widget.onSelect();
              _dragStart = d.globalPosition;
              _posAtDragStart = _pos;
            },
            onPanUpdate: (d) {
              if (widget.onMultiMoveUpdate != null) {
                widget.onMultiMoveUpdate!(d.delta); return;
              }
              final delta = d.globalPosition - _dragStart;
              setState(() { _pos = Offset(
                (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
                (_posAtDragStart.dy + delta.dy).clamp(0, widget.canvasH - _h),
              ); });
            },
            onPanEnd: (_) { _commit(); widget.onSaveSnapshot(); },
            child: Container(
              height: 24,
              color: widget.isSelected ? Colors.blue.shade50 : Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                Icon(Icons.drag_indicator, size: 12,
                    color: widget.isSelected ? Colors.blue : Colors.grey),
                const SizedBox(width: 4),
                Expanded(child: Text(widget.item.title,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        ),
        // Quill editor body
        Expanded(child: Container(
          color: Colors.white, padding: const EdgeInsets.all(4),
          child: QuillEditor(
            controller: widget.item.controller!,
            focusNode: widget.item.focusNode!,
            scrollController: widget.item.scrollController!,
            config: QuillEditorConfig(
              scrollable: true, expands: true, autoFocus: false, padding: EdgeInsets.zero,
              placeholder: widget.item.title,
              customStyleBuilder: (attribute) {
                if (attribute.key == Attribute.font.key) {
                  final family = attribute.value as String?;
                  if (family != null) return TextStyle(fontFamily: family);
                }
                return const TextStyle();
              },
            ),
          ),
        )),
      ]);
    }

    // All non-text shapes — move cursor on entire body
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        onPanStart: (d) {
          widget.onSelect();
          _dragStart = d.globalPosition;
          _posAtDragStart = _pos;
        },
        onPanUpdate: (d) {
          if (widget.onMultiMoveUpdate != null) {
            widget.onMultiMoveUpdate!(d.delta); return;
          }
          final delta = d.globalPosition - _dragStart;
          setState(() { _pos = Offset(
            (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
            (_posAtDragStart.dy + delta.dy).clamp(0, widget.canvasH - _h),
          ); });
        },
        onPanEnd: (_) { _commit(); widget.onSaveSnapshot(); },
        child: _buildShapeBody(),
      ),
    );
  }

  Widget _buildShapeBody() {
    final vertices = _shapeVertices(widget.item.type);
    if (vertices.isNotEmpty) {
      return SizedBox.expand(  // ← forces CustomPaint to fill parent
        child: CustomPaint(
          painter: _ShapePainter(
            vertices: vertices,
            fillColor: widget.item.color,
            strokeColor: widget.item.borderColor,
            strokeWidth: widget.item.borderWidth,
          ),
        ),
      );
    }

    switch (widget.item.type) {
      case CanvasItemType.line:
        return Container(
            height: widget.item.borderWidth.clamp(1, 12),
            color: widget.item.borderColor);
      case CanvasItemType.rectangle:
        return Container(decoration: BoxDecoration(
            color: widget.item.color,
            border: Border.all(
                color: widget.item.borderColor, width: widget.item.borderWidth)));
      case CanvasItemType.circle:
        return Container(decoration: BoxDecoration(
            color: widget.item.color, shape: BoxShape.circle,
            border: Border.all(
                color: widget.item.borderColor, width: widget.item.borderWidth)));
      case CanvasItemType.imageBox:
        return Container(
          decoration: BoxDecoration(color: widget.item.color,
              border: Border.all(color: widget.item.borderColor)),
          child: widget.item.imageBytes != null
              ? Image.memory(widget.item.imageBytes!, fit: BoxFit.cover)
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.image_outlined, size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 4),
            Text('Upload Image',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
        );
      case CanvasItemType.icon:
        return Center(child: Icon(widget.item.iconData ?? Icons.star,
            size: _w * 0.7, color: widget.item.borderColor));
      default:
        return const SizedBox();
    }
  }

  // ── Resize handles ────────────────────────────

  List<Widget> _buildResizeHandles() {
    const hit = 24.0, vis = 10.0, h = hit / 2;
    final handles = {
      ResizeHandle.topLeft:     Offset(-h, -h),
      ResizeHandle.top:         Offset(_w / 2 - h, -h),
      ResizeHandle.topRight:    Offset(_w - h, -h),
      ResizeHandle.right:       Offset(_w - h, _h / 2 - h),
      ResizeHandle.bottomRight: Offset(_w - h, _h - h),
      ResizeHandle.bottom:      Offset(_w / 2 - h, _h - h),
      ResizeHandle.bottomLeft:  Offset(-h, _h - h),
      ResizeHandle.left:        Offset(-h, _h / 2 - h),
    };
    final cursors = {
      ResizeHandle.topLeft:     SystemMouseCursors.resizeUpLeft,
      ResizeHandle.top:         SystemMouseCursors.resizeUp,
      ResizeHandle.topRight:    SystemMouseCursors.resizeUpRight,
      ResizeHandle.right:       SystemMouseCursors.resizeRight,
      ResizeHandle.bottomRight: SystemMouseCursors.resizeDownRight,
      ResizeHandle.bottom:      SystemMouseCursors.resizeDown,
      ResizeHandle.bottomLeft:  SystemMouseCursors.resizeDownLeft,
      ResizeHandle.left:        SystemMouseCursors.resizeLeft,
    };
    return handles.entries.map((e) {
      final handle = e.key;
      return Positioned(left: e.value.dx, top: e.value.dy,
        child: MouseRegion(cursor: cursors[handle]!,
          child: GestureDetector(
            onPanStart: (d) {
              _activeHandle = handle; _resizeOrigin = d.globalPosition;
              _posAtDragStart = _pos; _wAtResize = _w; _hAtResize = _h;
            },
            onPanUpdate: (d) {
              if (_activeHandle != handle) return;
              _onResizeUpdate(handle, d.globalPosition - _resizeOrigin);
            },
            onPanEnd: (_) { _activeHandle = null; _commit(); widget.onSaveSnapshot(); },
            child: SizedBox(width: hit, height: hit,
                child: Center(child: Container(width: vis, height: vis,
                    decoration: BoxDecoration(color: Colors.white,
                        border: Border.all(color: Colors.blue, width: 1.5),
                        borderRadius: BorderRadius.circular(2))))),
          ),
        ),
      );
    }).toList();
  }
}

class _ShapePainter extends CustomPainter {
  final List<Offset> vertices;
  final Color fillColor, strokeColor;
  final double strokeWidth;

  _ShapePainter({
    required this.vertices, required this.fillColor,
    required this.strokeColor, required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;
    final path = Path();
    path.moveTo(vertices.first.dx * size.width, vertices.first.dy * size.height);
    for (final v in vertices.skip(1)) {
      path.lineTo(v.dx * size.width, v.dy * size.height);
    }
    path.close();

    if (fillColor != Colors.transparent) {
      canvas.drawPath(path, Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill);
    }
    canvas.drawPath(path, Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.vertices != vertices || old.fillColor != fillColor ||
          old.strokeColor != strokeColor || old.strokeWidth != strokeWidth;
}