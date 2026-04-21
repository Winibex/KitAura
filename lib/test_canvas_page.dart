// lib/test_canvas_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────
class CvSection {
  String title;
  Offset position;
  double width;
  double height;
  final QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final String id;

  CvSection({
    required this.title,
    required this.position,
    this.width = 240,
    this.height = 160,
  })  : controller = QuillController.basic(),
        focusNode = FocusNode(),
        scrollController = ScrollController(),
        id = UniqueKey().toString();

  void dispose() {
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
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
  // A4 canvas dimensions in logical pixels (scaled down from 595x842)
  static const double canvasW = 595;
  static const double canvasH = 842;

  final List<CvSection> _sections = [];
  String? _focusedId;
  Key _toolbarKey = UniqueKey();

  // Global styles
  String _globalFont = 'OpenSans';
  double _globalFontSize = 12;

  static const Map<String, String> _fontItems = {
    'Arial': 'Arial',
    'Open Sans': 'OpenSans',
    'Poppins': 'Poppins',
    'Sekuya': 'Sekuya',
  };

  // PDF fonts
  final Map<String, pw.Font> _pdfFonts = {};
  bool _fontsLoaded = false;

  @override
  void initState() {
    super.initState();
    // Place default sections at sensible starting positions
    _addSection(title: 'Personal Info', position: const Offset(20, 20), width: 555, height: 80);
    _addSection(title: 'Summary',       position: const Offset(20, 120), width: 555, height: 100);
    _addSection(title: 'Experience',    position: const Offset(20, 240), width: 340, height: 180);
    _addSection(title: 'Education',     position: const Offset(20, 440), width: 340, height: 140);
    _addSection(title: 'Skills',        position: const Offset(375, 240), width: 200, height: 340);
    _preloadFonts();
  }

  @override
  void dispose() {
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  // ── Section management ──────────────────────

  void _addSection({
    String? title,
    Offset position = const Offset(20, 20),
    double width = 240,
    double height = 160,
  })
  {
    final section = CvSection(
      title: title ?? 'New Section',
      position: position,
      width: width,
      height: height,
    );
    section.focusNode.addListener(() {
      if (section.focusNode.hasFocus && _focusedId != section.id) {
        setState(() {
          _focusedId = section.id;
          _toolbarKey = UniqueKey();
        });
      }
    });
    setState(() {
      _sections.add(section);
      _focusedId = section.id;
      _toolbarKey = UniqueKey();
    });
  }

  void _removeSection(String id) {
    if (_sections.length <= 1) return;
    final idx = _sections.indexWhere((s) => s.id == id);
    if (idx == -1) return;
    _sections[idx].dispose();
    _sections.removeAt(idx);
    setState(() {
      _focusedId = _sections.isNotEmpty ? _sections.last.id : null;
      _toolbarKey = UniqueKey();
    });
  }

  void _renameSection(CvSection section) async {
    final tc = TextEditingController(text: section.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Section'),
        content: TextField(
          controller: tc,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, tc.text), child: const Text('OK')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      setState(() => section.title = result.trim());
    }
  }

  CvSection? get _focusedSection =>
      _sections.where((s) => s.id == _focusedId).firstOrNull;

  // ── Global styles ───────────────────────────

  void _applyGlobalFont(String family) {
    setState(() => _globalFont = family);
    for (final s in _sections) {
      final len = s.controller.document.length;
      if (len <= 1) continue;
      s.controller.formatText(0, len - 1, Attribute.fromKeyValue('font', family));
    }
  }

  void _applyGlobalFontSize(double size) {
    setState(() => _globalFontSize = size);
    for (final s in _sections) {
      final len = s.controller.document.length;
      if (len <= 1) continue;
      s.controller.formatText(0, len - 1, Attribute.fromKeyValue('size', '${size.toInt()}pt'));
    }
  }

  // ── PDF ─────────────────────────────────────

  Future<void> _preloadFonts() async {
    try {
      Future<pw.Font> load(String p) async =>
          pw.Font.ttf(await rootBundle.load(p));
      _pdfFonts['Arial']    = await load('assets/fonts/Arial.ttf');
      _pdfFonts['OpenSans'] = await load('assets/fonts/OpenSans.ttf');
      _pdfFonts['Poppins']  = await load('assets/fonts/Poppins.ttf');
      _pdfFonts['Sekuya']   = await load('assets/fonts/Sekuya.ttf');
      if (mounted) setState(() => _fontsLoaded = true);
    } catch (e) {
      debugPrint('Font load error: $e');
    }
  }

  pw.Font _getFont(String? family) =>
      _pdfFonts[family] ?? _pdfFonts['OpenSans'] ?? _pdfFonts.values.first;

  List<pw.InlineSpan> _deltaToSpans(CvSection section) {
    final delta = section.controller.document.toDelta();
    final List<pw.InlineSpan> spans = [];
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
    return spans;
  }

  Future<Uint8List> _buildPdf() async {
    // Scale factor: canvas is 595x842 logical px = actual A4 PDF points
    // So 1:1 mapping works perfectly
    const double scale = 1.0;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) {
          return pw.Stack(
            children: _sections.map((section) {
              final spans = _deltaToSpans(section);
              return pw.Positioned(
                left: section.position.dx * scale,
                top: section.position.dy * scale,
                child: pw.Container(
                  width: section.width * scale,
                  height: section.height * scale,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Section title
                      pw.Text(
                        section.title.toUpperCase(),
                        style: pw.TextStyle(
                          font: _getFont('OpenSans'),
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                      pw.SizedBox(height: 2),
                      // Content
                      if (spans.isNotEmpty)
                        pw.RichText(
                          text: pw.TextSpan(
                            children: spans,
                            style: pw.TextStyle(
                              font: _getFont(_globalFont),
                              fontSize: _globalFontSize,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
    return doc.save();
  }

  Future<void> _exportPdf() async {
    if (!_fontsLoaded) return;
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: 'kitaura_cv.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF error: $e')));
      }
    }
  }

  // ── UI ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final focused = _focusedSection;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 3: Free Canvas CV'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Section',
            onPressed: () => _addSection(
              position: const Offset(40, 40),
              width: 240,
              height: 160,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Toolbar — bound to focused section
                if (focused != null)
                  Container(
                    color: Colors.white,
                    child: QuillSimpleToolbar(
                      key: _toolbarKey,
                      controller: focused.controller,
                      config: QuillSimpleToolbarConfig(
                        toolbarSize: 36,
                        buttonOptions: QuillSimpleToolbarButtonOptions(
                          fontFamily: QuillToolbarFontFamilyButtonOptions(
                            items: _fontItems,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    height: 36,
                    color: Colors.white,
                    alignment: Alignment.center,
                    child: const Text('Click a section to edit',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),

                const Divider(height: 1),

                // Global styles
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Global Styles',
                          style: TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w700, color: Colors.black54)),
                      const SizedBox(height: 8),
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

                const Divider(height: 1),

                // Section list
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      const Text('Sections',
                          style: TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w700, color: Colors.black54)),
                      const Spacer(),
                      InkWell(
                        onTap: () => _addSection(
                            position: const Offset(40, 40), width: 240, height: 160),
                        child: const Icon(Icons.add, size: 18, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _sections.length,
                    itemBuilder: (ctx, i) {
                      final s = _sections[i];
                      final isFocused = s.id == _focusedId;
                      return ListTile(
                        dense: true,
                        selected: isFocused,
                        selectedTileColor: Colors.blue.shade50,
                        title: Text(s.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isFocused ? FontWeight.w600 : FontWeight.normal,
                              color: isFocused ? Colors.blue.shade800 : Colors.black87,
                            )),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                                onTap: () => _renameSection(s),
                                child: const Icon(Icons.edit, size: 14, color: Colors.grey)),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: _sections.length > 1 ? () => _removeSection(s.id) : null,
                              child: Icon(Icons.close, size: 14,
                                  color: _sections.length > 1
                                      ? Colors.red.shade300 : Colors.grey.shade300),
                            ),
                          ],
                        ),
                        onTap: () {
                          s.focusNode.requestFocus();
                          setState(() {
                            _focusedId = s.id;
                            _toolbarKey = UniqueKey();
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── RIGHT PANEL — Free Canvas ───────
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
                            // A4 white page
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(50),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Sections
                            ..._sections.map((section) =>
                                _buildDraggableSection(section)),
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

  Widget _buildDraggableSection(CvSection section) {
    return _DraggableSection(
      key: ValueKey(section.id),
      section: section,
      isFocused: section.id == _focusedId,
      canvasW: canvasW,
      canvasH: canvasH,
      onFocus: () => setState(() {
        _focusedId = section.id;
        _toolbarKey = UniqueKey();
      }),
      onRename: () => _renameSection(section),
      onDelete: () => _removeSection(section.id),
      canDelete: _sections.length > 1,
    );
  }
}

// Add this at the bottom of test_canvas_page.dart, outside the State class

class _DraggableSection extends StatefulWidget {
  final CvSection section;
  final bool isFocused;
  final double canvasW;
  final double canvasH;
  final VoidCallback onFocus;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final bool canDelete;

  const _DraggableSection({
    required this.section,
    required this.isFocused,
    required this.canvasW,
    required this.canvasH,
    required this.onFocus,
    required this.onRename,
    required this.onDelete,
    required this.canDelete,
    super.key, // ADD THIS
  });

  @override
  State<_DraggableSection> createState() => _DraggableSectionState();
}

class _DraggableSectionState extends State<_DraggableSection> {
  // Local position/size — no parent setState during drag
  late Offset _position;
  late double _width;
  late double _height;

  // Resize tracking
  Offset _resizeStart = Offset.zero;
  double _resizeStartW = 0;
  double _resizeStartH = 0;

  @override
  void initState() {
    super.initState();
    _position = widget.section.position;
    _width    = widget.section.width;
    _height   = widget.section.height;
  }

  void _commitToModel() {
    // Write back to model only when gesture ends
    widget.section.position = _position;
    widget.section.width    = _width;
    widget.section.height   = _height;
  }

  @override
  Widget build(BuildContext context) {
    final isFocused = widget.isFocused;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      width: _width,
      height: _height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main container
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: isFocused ? Colors.blue : Colors.grey.shade300,
                width: isFocused ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag handle header ──
                GestureDetector(
                  onPanUpdate: (details) {
                    // Only local setState — no parent rebuild
                    setState(() {
                      final newX = (_position.dx + details.delta.dx)
                          .clamp(0.0, widget.canvasW - _width);
                      final newY = (_position.dy + details.delta.dy)
                          .clamp(0.0, widget.canvasH - _height);
                      _position = Offset(newX, newY);
                    });
                  },
                  onPanEnd: (_) => _commitToModel(),
                  onTapDown: (_) => widget.onFocus(),
                  child: Container(
                    height: 28,
                    color: isFocused ? Colors.blue.shade50 : Colors.grey.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(Icons.drag_indicator,
                            size: 14,
                            color: isFocused ? Colors.blue.shade400 : Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.section.title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isFocused
                                  ? Colors.blue.shade800
                                  : Colors.grey.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: widget.onRename,
                          child: const Icon(Icons.edit, size: 12, color: Colors.grey),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: widget.canDelete ? widget.onDelete : null,
                          child: Icon(Icons.close,
                              size: 12,
                              color: widget.canDelete
                                  ? Colors.red.shade300
                                  : Colors.grey.shade200),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Quill Editor ──
                Expanded(
                  child: GestureDetector(
                    onTapDown: (_) {
                      widget.onFocus();
                      widget.section.focusNode.requestFocus();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: QuillEditor(
                        controller: widget.section.controller,
                        focusNode: widget.section.focusNode,
                        scrollController: widget.section.scrollController,
                        config: QuillEditorConfig(
                          scrollable: true,
                          expands: true,
                          autoFocus: false,
                          padding: EdgeInsets.zero,
                          placeholder: widget.section.title,
                          customStyleBuilder: (attribute) {
                            if (attribute.key == Attribute.font.key) {
                              final family = attribute.value as String?;
                              if (family != null) {
                                return TextStyle(fontFamily: family);
                              }
                            }
                            return const TextStyle();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Resize handle ──
          Positioned(
            right: -6,
            bottom: -6,
            child: GestureDetector(
              onPanStart: (details) {
                _resizeStart  = details.globalPosition;
                _resizeStartW = _width;
                _resizeStartH = _height;
              },
              onPanUpdate: (details) {
                setState(() {
                  final dx = details.globalPosition.dx - _resizeStart.dx;
                  final dy = details.globalPosition.dy - _resizeStart.dy;
                  _width  = (_resizeStartW + dx)
                      .clamp(120.0, widget.canvasW - _position.dx);
                  _height = (_resizeStartH + dy)
                      .clamp(60.0, widget.canvasH - _position.dy);
                });
              },
              onPanEnd: (_) => _commitToModel(),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: isFocused ? Colors.blue : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Icon(Icons.open_in_full, size: 8, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}