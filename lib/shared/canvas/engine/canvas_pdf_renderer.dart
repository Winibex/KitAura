// lib/shared/canvas/engine/canvas_pdf_renderer.dart
//
// PDF rendering extracted from canvas_controller.dart during E1 file
// structure cleanup. This is a `part of` claude_controller.dart — same
// library, full access to private members and the `pdfFonts` / `fontsLoaded`
// fields that still live on the main controller.
//
// Pure output: these methods read canvas state and produce PDF widgets/bytes.
// They never mutate the canvas. Safe to call from any thread/context that
// can read the controller.

part of 'canvas_controller.dart';

extension CanvasPdfRenderer on CanvasController {

  // ─── FONT PRELOAD ─────────────────────────────────────────────────────

  /// Loads the four custom TTF fonts from assets and stores them in the
  /// `pdfFonts` map on the controller. Sets `fontsLoaded = true` when done.
  /// Called once during canvas init.
  Future<void> preloadFonts() async {
    try {
      Future<pw.Font> load(String p) async =>
          pw.Font.ttf(await rootBundle.load(p));
      pdfFonts['Arial']    = await load('assets/fonts/Arial.ttf');
      pdfFonts['OpenSans'] = await load('assets/fonts/OpenSans.ttf');
      pdfFonts['Poppins']  = await load('assets/fonts/Poppins.ttf');
      pdfFonts['Sekuya']   = await load('assets/fonts/Sekuya.ttf');
      fontsLoaded = true;
      notifyFromExtension();
    } catch (e) {
      debugPrint('Font load error: $e');
    }
  }

  /// Returns the loaded pw.Font for the given family name, with a
  /// safe fallback chain: requested → OpenSans → any loaded font.
  pw.Font getFont(String? f) =>
      pdfFonts[f] ?? pdfFonts['OpenSans'] ?? pdfFonts.values.first;

  /// Converts a Flutter Color into a PdfColor.
  PdfColor toPdfColor(Color c) => PdfColor(c.r, c.g, c.b, c.a);

  // ─── PER-ITEM PDF WIDGET BUILDER ──────────────────────────────────────

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

        // 2) Build one widget per paragraph, with 8px gaps between them.
        final paraWidgets = <pw.Widget>[];
        for (int p = 0; p < paragraphs.length; p++) {
          final spans = paragraphs[p];
          if (p > 0) {
            paraWidgets.add(pw.SizedBox(height: AutoHeight.paragraphSpacing));
          }
          if (spans.isEmpty) {
            paraWidgets.add(pw.SizedBox(height: AutoHeight.defaultFontSize * AutoHeight.textLineHeight));
          } else {
            paraWidgets.add(pw.RichText(
              text: pw.TextSpan(children: List.of(spans)),
            ));
          }
        }

        // 3) Wrap with the same 10px vertical padding (textVPad) the engine adds.
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
            border: item.borderWidth > 0
                ? pw.Border.all(color: toPdfColor(item.borderColor), width: item.borderWidth)
                : null,
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
              c: const pw.FlexColumnWidth(1),
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

  // ─── FULL DOCUMENT PDF BUILD ──────────────────────────────────────────

  Future<Uint8List> buildPdf({bool showWatermark = false}) async {
    final doc = pw.Document();
    for (int p = 0; p < totalPages; p++) {
      final pageOffset = p * CanvasController.canvasH;
      debugPrint('📄 PDF page $p: canvasH=${CanvasController.canvasH} pageOffset=$pageOffset '
          'a4=${PdfPageFormat.a4.width.toStringAsFixed(1)}x${PdfPageFormat.a4.height.toStringAsFixed(1)} '
          'items=${items.where((i) => (i.position.dy / CanvasController.canvasH).floor() == p).length}');
      final pageItems = items.where((item) {
        final itemPage = (item.position.dy / CanvasController.canvasH).floor();
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
}