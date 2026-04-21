// lib/test_pdf_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class TestPdfPage extends StatefulWidget {
  final QuillController controller;
  const TestPdfPage({super.key, required this.controller});

  @override
  State<TestPdfPage> createState() => _TestPdfPageState();
}

class _TestPdfPageState extends State<TestPdfPage> {
  bool _isGenerating = false;
  bool _fontsLoaded = false;
  Uint8List? _pdfBytes;

  // Normal and bold variants keyed by Delta font attribute value
  final Map<String, pw.Font> _normalFonts = {};
  final Map<String, pw.Font> _boldFonts = {};

  @override
  void initState() {
    super.initState();
    _preloadFonts();
  }

  Future<pw.Font> _loadFont(String path) async {
    final data = await rootBundle.load(path);
    return pw.Font.ttf(data);
  }

  Future<void> _preloadFonts() async {
    try {
      _normalFonts['Arial']   = await _loadFont('assets/fonts/Arial.ttf');
      _normalFonts['OpenSans'] = await _loadFont('assets/fonts/OpenSans.ttf');
      _normalFonts['Poppins'] = await _loadFont('assets/fonts/Poppins.ttf');
      _normalFonts['Sekuya']  = await _loadFont('assets/fonts/Sekuya.ttf');

      // Reuse normal as bold until you have bold .ttf files
      _boldFonts.addAll(_normalFonts);

      if (mounted) setState(() => _fontsLoaded = true);
    } catch (e) {
      debugPrint('Font preload error: $e');
    }
  }

  pw.Font _getFont(String? family, {bool bold = false}) {
    final map = bold ? _boldFonts : _normalFonts;
    return map[family] ?? _normalFonts['OpenSans'] ?? _normalFonts.values.first;
  }

  /// Core fix: we walk the Delta ops ourselves and build pw.RichText spans.
  /// This bypasses flutter_quill_to_pdf entirely and gives us full font control.
  Future<Uint8List> _deltaTopdf() async {
    final delta = widget.controller.document.toDelta();
    final doc = pw.Document();

    // We'll collect lines. Each line is a list of pw.TextSpan.
    final List<List<pw.InlineSpan>> lines = [[]];

    for (final op in delta.toList()) {
      if (op.isInsert) {
        final text = op.data as String? ?? '';
        final attrs = op.attributes;

        final String? fontFamily = attrs?['font'] as String?;
        final bool isBold       = attrs?['bold'] == true;
        final bool isItalic     = attrs?['italic'] == true;
        final num? fontSize     = attrs?['size'] as num?;

        final pw.Font font = _getFont(fontFamily, bold: isBold);

        // Split on newlines — each \n starts a new line in the PDF
        final parts = text.split('\n');
        for (int i = 0; i < parts.length; i++) {
          if (i > 0) {
            lines.add([]); // new line
          }
          if (parts[i].isNotEmpty) {
            lines.last.add(
              pw.TextSpan(
                text: parts[i],
                style: pw.TextStyle(
                  font: font,
                  fontSize: fontSize?.toDouble() ?? 12,
                  fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
                ),
              ),
            );
          }
        }
      }
    }

    // Build PDF widgets from lines
    final pw.Font defaultFont = _getFont('OpenSans');
    final List<pw.Widget> pdfWidgets = [];

    for (final spans in lines) {
      if (spans.isEmpty) {
        // Empty line = spacing
        pdfWidgets.add(pw.SizedBox(height: 6));
      } else {
        pdfWidgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.RichText(
              text: pw.TextSpan(
                children: spans,
                style: pw.TextStyle(font: defaultFont, fontSize: 12),
              ),
            ),
          ),
        );
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pdfWidgets,
      ),
    );

    return doc.save();
  }

  Future<void> _generatePdf() async {
    if (!_fontsLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fonts still loading...')),
      );
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final bytes = await _deltaTopdf();
      setState(() => _pdfBytes = bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF generated!')),
        );
      }
    } catch (e, stack) {
      debugPrint('PDF error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (_pdfBytes == null) return;
    await Printing.sharePdf(bytes: _pdfBytes!, filename: 'my_cv.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test 2: PDF Export'),
        actions: [
          if (_pdfBytes != null)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _downloadPdf,
              tooltip: 'Download PDF',
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 200,
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current Content:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: QuillEditor.basic(
                    controller: widget.controller,
                    config: const QuillEditorConfig(
                      scrollable: true,
                      autoFocus: false,
                      expands: true,
                      padding: EdgeInsets.zero,
                      placeholder: 'No content yet — go to Test 1 first',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (!_fontsLoaded)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading fonts...'),
                      ],
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: (_isGenerating || !_fontsLoaded) ? null : _generatePdf,
                  icon: _isGenerating
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf),
                  label: Text(_isGenerating ? 'Generating...' : 'Generate PDF'),
                ),
              ],
            ),
          ),
          if (_pdfBytes != null)
            Expanded(
              child: Column(
                children: [
                  const Text('PDF Preview:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: PdfPreview(
                      build: (format) => _pdfBytes!,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}