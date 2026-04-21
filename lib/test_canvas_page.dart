// lib/test_canvas_page.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────
// Enums & Models
// ─────────────────────────────────────────────
enum CanvasItemType { textSection, line, rectangle, circle, imageBox, icon }

enum ResizeHandle { topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left }

class CanvasItem {
  final String id;
  CanvasItemType type;
  Offset position;
  double width;
  double height;
  Color color;
  Color borderColor;
  double borderWidth;
  Uint8List? imageBytes;
  IconData? iconData;
  String title;

  // Only for textSection
  QuillController? controller;
  FocusNode? focusNode;
  ScrollController? scrollController;

  CanvasItem({
    required this.type,
    required this.position,
    required this.width,
    required this.height,
    this.color = Colors.transparent,
    this.borderColor = Colors.grey,
    this.borderWidth = 1,
    this.imageBytes,
    this.iconData,
    this.title = '',
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
  Key _toolbarKey = UniqueKey();

  String _globalFont = 'OpenSans';
  double _globalFontSize = 12;

  static const Map<String, String> _fontItems = {
    'Arial': 'Arial',
    'Open Sans': 'OpenSans',
    'Poppins': 'Poppins',
    'Sekuya': 'Sekuya',
  };

  final Map<String, pw.Font> _pdfFonts = {};
  bool _fontsLoaded = false;

  @override
  void initState() {
    super.initState();
    _addTextSection(title: 'Personal Info', position: const Offset(20, 20), width: 555, height: 80);
    _addTextSection(title: 'Summary', position: const Offset(20, 120), width: 555, height: 100);
    _addTextSection(title: 'Experience', position: const Offset(20, 240), width: 340, height: 180);
    _addTextSection(title: 'Skills', position: const Offset(375, 240), width: 200, height: 180);
    _preloadFonts();
  }

  @override
  void dispose() {
    for (final item in _items) item.dispose();
    super.dispose();
  }

  // ── Item management ─────────────────────────

  void _addTextSection({
    String title = 'New Section',
    Offset position = const Offset(40, 40),
    double width = 240,
    double height = 160,
  }) {
    final item = CanvasItem(
      type: CanvasItemType.textSection,
      position: position,
      width: width,
      height: height,
      title: title,
    );
    item.focusNode!.addListener(() {
      if (item.focusNode!.hasFocus && _selectedId != item.id) {
        setState(() { _selectedId = item.id; _toolbarKey = UniqueKey(); });
      }
    });
    setState(() { _items.add(item); _selectedId = item.id; _toolbarKey = UniqueKey(); });
  }

  void _addShape(CanvasItemType type) {
    final defaults = <CanvasItemType, Map<String, dynamic>>{
      CanvasItemType.line:      {'w': 200.0, 'h': 4.0,   'color': Colors.black, 'border': Colors.black},
      CanvasItemType.rectangle: {'w': 160.0, 'h': 100.0, 'color': Colors.blue.shade100, 'border': Colors.blue},
      CanvasItemType.circle:    {'w': 100.0, 'h': 100.0, 'color': Colors.green.shade100, 'border': Colors.green},
      CanvasItemType.imageBox:  {'w': 160.0, 'h': 120.0, 'color': Colors.grey.shade200, 'border': Colors.grey},
      CanvasItemType.icon:      {'w': 48.0,  'h': 48.0,  'color': Colors.transparent, 'border': Colors.transparent},
    };
    final d = defaults[type]!;
    final item = CanvasItem(
      type: type,
      position: const Offset(80, 80),
      width: d['w'] as double,
      height: d['h'] as double,
      color: d['color'] as Color,
      borderColor: d['border'] as Color,
      iconData: type == CanvasItemType.icon ? Icons.star : null,
      title: type == CanvasItemType.imageBox ? 'Image' : '',
    );
    setState(() { _items.add(item); _selectedId = item.id; });
  }

  void _deleteSelected() {
    if (_selectedId == null) return;
    final idx = _items.indexWhere((i) => i.id == _selectedId);
    if (idx == -1) return;
    _items[idx].dispose();
    _items.removeAt(idx);
    setState(() { _selectedId = _items.isNotEmpty ? _items.last.id : null; _toolbarKey = UniqueKey(); });
  }

  CanvasItem? get _selected => _items.where((i) => i.id == _selectedId).firstOrNull;

  // ── Image upload ────────────────────────────

  Future<void> _uploadImage(CanvasItem item) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() => item.imageBytes = result.files.single.bytes);
    }
  }

  // ── Color picker ────────────────────────────

  void _showColorPicker({required bool isBorder}) {
    final item = _selected;
    if (item == null) return;
    Color current = isBorder ? item.borderColor : item.color;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBorder ? 'Border Color' : 'Fill Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: (c) => current = c,
            enableAlpha: true,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() {
                if (isBorder) item.borderColor = current;
                else item.color = current;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ── Icon picker ─────────────────────────────

  void _showIconPicker(CanvasItem item) {
    final icons = <IconData>[
      Icons.star, Icons.favorite, Icons.phone, Icons.email,
      Icons.location_on, Icons.work, Icons.school, Icons.person,
      Icons.link, Icons.language, Icons.code, Icons.build,
      Icons.check_circle, Icons.arrow_forward, Icons.lightbulb, Icons.emoji_events,
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick an Icon'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: icons.map((ic) => GestureDetector(
            onTap: () { setState(() => item.iconData = ic); Navigator.pop(ctx); },
            child: Icon(ic, size: 32, color: item.borderColor),
          )).toList(),
        ),
      ),
    );
  }

  // ── Global styles ───────────────────────────

  void _applyGlobalFont(String family) {
    setState(() => _globalFont = family);
    for (final item in _items) {
      if (!item.isText) continue;
      final len = item.controller!.document.length;
      if (len <= 1) continue;
      item.controller!.formatText(0, len - 1, Attribute.fromKeyValue('font', family));
    }
  }

  void _applyGlobalFontSize(double size) {
    setState(() => _globalFontSize = size);
    for (final item in _items) {
      if (!item.isText) continue;
      final len = item.controller!.document.length;
      if (len <= 1) continue;
      item.controller!.formatText(0, len - 1, Attribute.fromKeyValue('size', '${size.toInt()}pt'));
    }
  }

  // ── PDF ─────────────────────────────────────

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

  pw.Font _getFont(String? family) =>
      _pdfFonts[family] ?? _pdfFonts['OpenSans'] ?? _pdfFonts.values.first;

  PdfColor _toPdfColor(Color c) =>
      PdfColor(c.red / 255, c.green / 255, c.blue / 255, c.alpha / 255);

  Future<Uint8List> _buildPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Stack(
        children: _items.map((item) => _itemToPdf(item)).whereType<pw.Widget>().toList(),
      ),
    ));
    return doc.save();
  }

  pw.Widget? _itemToPdf(CanvasItem item) {
    switch (item.type) {

      case CanvasItemType.textSection:
        final delta = item.controller!.document.toDelta();
        final spans = <pw.InlineSpan>[];
        for (final op in delta.toList()) {
          if (!op.isInsert) continue;
          final text = (op.data as String? ?? '').replaceAll('\n', ' ');
          if (text.trim().isEmpty) continue;
          final attrs = op.attributes;
          spans.add(pw.TextSpan(
            text: text,
            style: pw.TextStyle(
              font: _getFont(attrs?['font'] as String? ?? _globalFont),
              fontSize: _globalFontSize,
              fontWeight: attrs?['bold'] == true ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontStyle: attrs?['italic'] == true ? pw.FontStyle.italic : pw.FontStyle.normal,
            ),
          ));
        }
        return pw.Positioned(
          left: item.position.dx,
          top: item.position.dy,
          child: pw.Container(
            width: item.width,
            height: item.height,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(item.title.toUpperCase(),
                    style: pw.TextStyle(font: _getFont('OpenSans'), fontSize: 8,
                        fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 2),
                if (spans.isNotEmpty)
                  pw.RichText(text: pw.TextSpan(
                    children: spans,
                    style: pw.TextStyle(font: _getFont(_globalFont), fontSize: _globalFontSize),
                  )),
              ],
            ),
          ),
        );

      case CanvasItemType.line:
        return pw.Positioned(
          left: item.position.dx,
          top: item.position.dy,
          child: pw.Container(
            width: item.width,
            height: item.borderWidth.clamp(1, 8),
            color: _toPdfColor(item.borderColor),
          ),
        );

      case CanvasItemType.rectangle:
        return pw.Positioned(
          left: item.position.dx,
          top: item.position.dy,
          child: pw.Container(
            width: item.width,
            height: item.height,
            decoration: pw.BoxDecoration(
              color: _toPdfColor(item.color),
              border: pw.Border.all(
                color: _toPdfColor(item.borderColor),
                width: item.borderWidth,
              ),
            ),
          ),
        );

      case CanvasItemType.circle:
        return pw.Positioned(
          left: item.position.dx,
          top: item.position.dy,
          child: pw.Container(
            width: item.width,
            height: item.height,
            decoration: pw.BoxDecoration(
              color: _toPdfColor(item.color),
              shape: pw.BoxShape.circle,
              border: pw.Border.all(
                color: _toPdfColor(item.borderColor),
                width: item.borderWidth,
              ),
            ),
          ),
        );

      case CanvasItemType.imageBox:
        if (item.imageBytes != null) {
          return pw.Positioned(
            left: item.position.dx,
            top: item.position.dy,
            child: pw.Container(
              width: item.width,
              height: item.height,
              child: pw.Image(pw.MemoryImage(item.imageBytes!), fit: pw.BoxFit.cover),
            ),
          );
        }
        return pw.Positioned(
          left: item.position.dx,
          top: item.position.dy,
          child: pw.Container(
            width: item.width,
            height: item.height,
            decoration: pw.BoxDecoration(
              color: _toPdfColor(item.color),
              border: pw.Border.all(color: _toPdfColor(item.borderColor)),
            ),
          ),
        );

      case CanvasItemType.icon:
      // Icons don't have a direct PDF equivalent — render as colored circle placeholder
        return pw.Positioned(
          left: item.position.dx,
          top: item.position.dy,
          child: pw.Container(
            width: item.width,
            height: item.height,
            decoration: pw.BoxDecoration(
              color: _toPdfColor(item.borderColor),
              shape: pw.BoxShape.circle,
            ),
          ),
        );
    }
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

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 3: Free Canvas CV'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _fontsLoaded ? _exportPdf : null,
          ),
        ],
      ),
      body: Row(
        children: [
          // ── LEFT PANEL ──────────────────────
          Container(
            width: 260,
            color: Colors.grey.shade100,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quill toolbar (text sections only)
                  if (selected?.isText == true)
                    Container(
                      color: Colors.white,
                      child: QuillSimpleToolbar(
                        key: _toolbarKey,
                        controller: selected!.controller!,
                        config: QuillSimpleToolbarConfig(
                          toolbarSize: 36,
                          buttonOptions: QuillSimpleToolbarButtonOptions(
                            fontFamily: QuillToolbarFontFamilyButtonOptions(items: _fontItems),
                          ),
                        ),
                      ),
                    ),

                  const Divider(height: 1),

                  // ── Add shapes panel ──
                  _panelHeader('Add Elements'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _addBtn('Text', Icons.text_fields, () => _addTextSection()),
                        _addBtn('Line', Icons.horizontal_rule, () => _addShape(CanvasItemType.line)),
                        _addBtn('Rect', Icons.rectangle_outlined, () => _addShape(CanvasItemType.rectangle)),
                        _addBtn('Circle', Icons.circle_outlined, () => _addShape(CanvasItemType.circle)),
                        _addBtn('Image', Icons.image_outlined, () => _addShape(CanvasItemType.imageBox)),
                        _addBtn('Icon', Icons.emoji_emotions_outlined, () => _addShape(CanvasItemType.icon)),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // ── Selected item properties ──
                  if (selected != null) ...[
                    _panelHeader('Properties  •  ${selected.title.isNotEmpty ? selected.title : selected.type.name}'),

                    // Delete button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _deleteSelected,
                          icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                          label: const Text('Delete', style: TextStyle(color: Colors.red, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ),

                    // Fill color (not for line/icon)
                    if (selected.type != CanvasItemType.line &&
                        selected.type != CanvasItemType.icon &&
                        selected.type != CanvasItemType.textSection)
                      _colorRow('Fill Color', selected.color, () => _showColorPicker(isBorder: false)),

                    // Border/line color
                    if (selected.type != CanvasItemType.textSection)
                      _colorRow(
                        selected.type == CanvasItemType.line ? 'Line Color' : 'Border Color',
                        selected.borderColor,
                            () => _showColorPicker(isBorder: true),
                      ),

                    // Border width slider (not for image/text)
                    if (selected.type == CanvasItemType.line ||
                        selected.type == CanvasItemType.rectangle ||
                        selected.type == CanvasItemType.circle)
                      _sliderRow(
                        selected.type == CanvasItemType.line ? 'Thickness' : 'Border Width',
                        selected.borderWidth,
                        1, 12,
                            (v) => setState(() => selected.borderWidth = v),
                      ),

                    // Image upload
                    if (selected.type == CanvasItemType.imageBox)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _uploadImage(selected),
                            icon: const Icon(Icons.upload, size: 14),
                            label: const Text('Upload Image', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ),

                    // Icon picker
                    if (selected.type == CanvasItemType.icon)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _showIconPicker(selected),
                            icon: const Icon(Icons.emoji_emotions_outlined, size: 14),
                            label: const Text('Change Icon', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ),

                    // Icon color
                    if (selected.type == CanvasItemType.icon)
                      _colorRow('Icon Color', selected.borderColor, () => _showColorPicker(isBorder: true)),
                  ],

                  const Divider(height: 1),

                  // ── Global text styles ──
                  if (_items.any((i) => i.isText)) ...[
                    _panelHeader('Global Text Styles'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Column(
                        children: [
                          Row(children: [
                            const Text('Font', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _globalFont,
                                isExpanded: true,
                                isDense: true,
                                items: _fontItems.entries.map((e) => DropdownMenuItem(
                                  value: e.value,
                                  child: Text(e.key, style: const TextStyle(fontSize: 12)),
                                )).toList(),
                                onChanged: (v) { if (v != null) _applyGlobalFont(v); },
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: [
                            const Text('Size', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 8),
                            DropdownButton<double>(
                              value: _globalFontSize,
                              isDense: true,
                              items: [10, 11, 12, 13, 14, 16, 18, 20, 24]
                                  .map((s) => DropdownMenuItem(
                                value: s.toDouble(),
                                child: Text('$s', style: const TextStyle(fontSize: 12)),
                              )).toList(),
                              onChanged: (v) { if (v != null) _applyGlobalFontSize(v); },
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── RIGHT PANEL — Canvas ─────────────
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
                        width: canvasW,
                        height: canvasH,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                onTapDown: (_) => setState(() => _selectedId = null),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    boxShadow: [BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    )],
                                  ),
                                ),
                              ),
                            ),
                            ..._items.map((item) => _CanvasItemWidget(
                              key: ValueKey(item.id),
                              item: item,
                              isSelected: item.id == _selectedId,
                              canvasW: canvasW,
                              canvasH: canvasH,
                              onSelect: () => setState(() {
                                _selectedId = item.id;
                                if (item.isText) _toolbarKey = UniqueKey();
                              }),
                              fontItems: _fontItems,
                              toolbarKey: _toolbarKey,
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
        ],
      ),
    );
  }

  // ── Left panel helpers ───────────────────────

  Widget _panelHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
    child: Text(title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black54)),
  );

  Widget _addBtn(String label, IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 72,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.blue),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );

  Widget _colorRow(String label, Color color, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const Spacer(),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 28,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _sliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: (max - min).toInt(),
                label: value.toStringAsFixed(0),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────
// Canvas Item Widget (self-contained, no parent rebuild on drag)
// ─────────────────────────────────────────────
class _CanvasItemWidget extends StatefulWidget {
  final CanvasItem item;
  final bool isSelected;
  final double canvasW;
  final double canvasH;
  final VoidCallback onSelect;
  final Map<String, String> fontItems;
  final Key toolbarKey;

  const _CanvasItemWidget({
    super.key,
    required this.item,
    required this.isSelected,
    required this.canvasW,
    required this.canvasH,
    required this.onSelect,
    required this.fontItems,
    required this.toolbarKey,
  });

  @override
  State<_CanvasItemWidget> createState() => _CanvasItemWidgetState();
}

class _CanvasItemWidgetState extends State<_CanvasItemWidget> {
  late Offset _pos;
  late double _w;
  late double _h;

  Offset _dragStart = Offset.zero;
  Offset _posAtDragStart = Offset.zero;
  double _wAtResizeStart = 0;
  double _hAtResizeStart = 0;
  Offset _resizeHandleStart = Offset.zero;
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
    // Sync if parent changed values (e.g. after add/delete)
    if (old.item.id != widget.item.id) {
      _pos = widget.item.position;
      _w   = widget.item.width;
      _h   = widget.item.height;
    }
  }

  void _commit() {
    widget.item.position = _pos;
    widget.item.width    = _w;
    widget.item.height   = _h;
  }

  void _onResizeUpdate(ResizeHandle handle, Offset delta) {
    double left  = _posAtDragStart.dx;
    double top   = _posAtDragStart.dy;
    double right = left + _wAtResizeStart;
    double bot   = top  + _hAtResizeStart;

    final dx = delta.dx;
    final dy = delta.dy;

    switch (handle) {
      case ResizeHandle.topLeft:     left += dx; top += dy; break;
      case ResizeHandle.top:         top += dy; break;
      case ResizeHandle.topRight:    right += dx; top += dy; break;
      case ResizeHandle.right:       right += dx; break;
      case ResizeHandle.bottomRight: right += dx; bot += dy; break;
      case ResizeHandle.bottom:      bot += dy; break;
      case ResizeHandle.bottomLeft:  left += dx; bot += dy; break;
      case ResizeHandle.left:        left += dx; break;
    }

    const minW = 40.0;
    const minH = 20.0;
    if (right - left < minW) { if (handle.name.contains('Left')) left = right - minW; else right = left + minW; }
    if (bot - top  < minH) { if (handle.name.contains('top'))  top  = bot  - minH; else bot  = top  + minH; }

    setState(() {
      _pos = Offset(left.clamp(0, widget.canvasW - minW), top.clamp(0, widget.canvasH - minH));
      _w   = (right - left).clamp(minW, widget.canvasW - _pos.dx);
      _h   = (bot   - top).clamp(minH, widget.canvasH - _pos.dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx,
      top:  _pos.dy,
      width: _w,
      height: _h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main item
          GestureDetector(
            onTapDown: (_) => widget.onSelect(),
            child: _buildItemBody(),
          ),

          // Selection border + drag via header
          if (widget.isSelected) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 1.5),
                  ),
                ),
              ),
            ),
            // 8 resize handles
            ..._buildResizeHandles(),
          ],
        ],
      ),
    );
  }

  Widget _buildItemBody() {
    switch (widget.item.type) {

      case CanvasItemType.textSection:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag header
            GestureDetector(
              onPanStart: (d) {
                widget.onSelect();
                _dragStart = d.globalPosition;
                _posAtDragStart = _pos;
              },
              onPanUpdate: (d) {
                final delta = d.globalPosition - _dragStart;
                setState(() {
                  _pos = Offset(
                    (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
                    (_posAtDragStart.dy + delta.dy).clamp(0, widget.canvasH - _h),
                  );
                });
              },
              onPanEnd: (_) => _commit(),
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
            Expanded(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(4),
                child: QuillEditor(
                  controller: widget.item.controller!,
                  focusNode: widget.item.focusNode!,
                  scrollController: widget.item.scrollController!,
                  config: QuillEditorConfig(
                    scrollable: true,
                    expands: true,
                    autoFocus: false,
                    padding: EdgeInsets.zero,
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
              ),
            ),
          ],
        );

      case CanvasItemType.line:
        return GestureDetector(
          onPanStart: (d) { widget.onSelect(); _dragStart = d.globalPosition; _posAtDragStart = _pos; },
          onPanUpdate: (d) {
            final delta = d.globalPosition - _dragStart;
            setState(() {
              _pos = Offset(
                (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
                (_posAtDragStart.dy + delta.dy).clamp(0, widget.canvasH - _h),
              );
            });
          },
          onPanEnd: (_) => _commit(),
          child: Container(
            width: _w,
            height: widget.item.borderWidth.clamp(1, 12),
            color: widget.item.borderColor,
          ),
        );

      case CanvasItemType.rectangle:
        return GestureDetector(
          onPanStart: (d) { widget.onSelect(); _dragStart = d.globalPosition; _posAtDragStart = _pos; },
          onPanUpdate: (d) {
            final delta = d.globalPosition - _dragStart;
            setState(() {
              _pos = Offset(
                (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
                (_posAtDragStart.dy + delta.dy).clamp(0, widget.canvasH - _h),
              );
            });
          },
          onPanEnd: (_) => _commit(),
          child: Container(
            decoration: BoxDecoration(
              color: widget.item.color,
              border: Border.all(color: widget.item.borderColor, width: widget.item.borderWidth),
            ),
          ),
        );

      case CanvasItemType.circle:
        return GestureDetector(
          onPanStart: (d) { widget.onSelect(); _dragStart = d.globalPosition; _posAtDragStart = _pos; },
          onPanUpdate: (d) {
            final delta = d.globalPosition - _dragStart;
            setState(() {
              _pos = Offset(
                (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
                (_posAtDragStart.dy + delta.dy).clamp(0, widget.canvasH - _h),
              );
            });
          },
          onPanEnd: (_) => _commit(),
          child: Container(
            decoration: BoxDecoration(
              color: widget.item.color,
              shape: BoxShape.circle,
              border: Border.all(color: widget.item.borderColor, width: widget.item.borderWidth),
            ),
          ),
        );

      case CanvasItemType.imageBox:
        return GestureDetector(
          onPanStart: (d) { widget.onSelect(); _dragStart = d.globalPosition; _posAtDragStart = _pos; },
          onPanUpdate: (d) {
            final delta = d.globalPosition - _dragStart;
            setState(() {
              _pos = Offset(
                (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
                (_posAtDragStart.dy + delta.dy).clamp(0, widget.canvasH - _h),
              );
            });
          },
          onPanEnd: (_) => _commit(),
          child: Container(
            decoration: BoxDecoration(
              color: widget.item.color,
              border: Border.all(color: widget.item.borderColor),
            ),
            child: widget.item.imageBytes != null
                ? Image.memory(widget.item.imageBytes!, fit: BoxFit.cover)
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_outlined, size: 32, color: Colors.grey.shade400),
                const SizedBox(height: 4),
                Text('Upload Image',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
        );

      case CanvasItemType.icon:
        return GestureDetector(
          onPanStart: (d) { widget.onSelect(); _dragStart = d.globalPosition; _posAtDragStart = _pos; },
          onPanUpdate: (d) {
            final delta = d.globalPosition - _dragStart;
            setState(() {
              _pos = Offset(
                (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
                (_posAtDragStart.dy + delta.dy).clamp(0, widget.canvasH - _h),
              );
            });
          },
          onPanEnd: (_) => _commit(),
          child: Center(
            child: Icon(
              widget.item.iconData ?? Icons.star,
              size: _w * 0.7,
              color: widget.item.borderColor,
            ),
          ),
        );
    }
  }

  List<Widget> _buildResizeHandles() {
    const s = 10.0; // handle size
    const h = s / 2;

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

    return handles.entries.map((entry) {
      final handle = entry.key;
      final offset = entry.value;
      return Positioned(
        left: offset.dx,
        top:  offset.dy,
        child: MouseRegion(
          cursor: cursors[handle]!,
          child: GestureDetector(
            onPanStart: (d) {
              _activeHandle = handle;
              _resizeHandleStart = d.globalPosition;
              _posAtDragStart    = _pos;
              _wAtResizeStart    = _w;
              _hAtResizeStart    = _h;
            },
            onPanUpdate: (d) {
              if (_activeHandle != handle) return;
              _onResizeUpdate(handle, d.globalPosition - _resizeHandleStart);
            },
            onPanEnd: (_) { _activeHandle = null; _commit(); },
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.blue, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}