// lib/shared/canvas/engine/reflow_engine.dart
//
// Repositions content after auto-height. Engine OWNS all vertical spacing
// (consistent rhythm), pins role:'hero' items to their original spot, pairs
// role:'heading' + role:'underline' (same `group`) into atomic blocks, and
// drops whole blocks to the next page with top+bottom margins (no edge bleed).
// Mutates items in place. Call autosizeAll() FIRST.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/canvas_item.dart';
import 'auto_height.dart';

class ReflowEngine {
  // ── Rhythm constants (the single source of spacing) ──────────────
  static const double topMargin = 50; // top of every page
  static const double bottomMargin = 65; // reserved at page bottom (no bleed)
  static const double headingGap = 8; // heading bottom → underline
  static const double afterUnderline = 12; // underline bottom → body
  static const double afterHeadingNoRule = 14; // heading → body (no underline)
  static const double sectionGap = 22; // between consecutive blocks
  static const double rowGap = 22; // between side-by-side rows
  static const double minSplitText = 30; // ~2 lines; fill pages tighter

  static void arrange(List<CanvasItem> items, double pageH) {
    if (items.isEmpty) return;

    debugPrint('🔧 REFLOW: ${items.length} items | '
        'heroes=${items.where((i) => i.role == "hero").length} | '
        'headings=${items.where((i) => i.role == "heading").length} | '
        'underlines=${items.where((i) => i.role == "underline").length}');

    debugPrint('📏 GEOMETRY: pageH=$pageH topMargin=$topMargin '
        'bottomMargin=$bottomMargin usableBottom=${pageH - bottomMargin} '
        'minSplitText=$minSplitText');

    final usableBottom = pageH - bottomMargin;

    bool xOverlap(CanvasItem a, CanvasItem b) =>
        !(a.position.dx + a.width <= b.position.dx ||
            b.position.dx + b.width <= a.position.dx);

    // Hero items: pinned, never moved, not part of flow.
    final heroes = items.where((i) => i.role == 'hero').toSet();

    // Top-band items: pinned at their template Y on page 1 (like heroes),
    // but content flows on the SAME page right after them — unlike heroes,
    // which own page 1 entirely.
    final topBand = items.where((i) => i.role == 'top_band').toSet();

    // Underlines are positioned relative to their heading, not flowed alone.
    final underlines = <String, CanvasItem>{}; // group -> underline
    for (final i in items) {
      if (i.role == 'underline' && i.group != null) underlines[i.group!] = i;
    }

    // Flowing content = text/table that isn't hero, isn't a top-band item,
    // and isn't an underline.
    final flow = items
        .where(
          (i) =>
      !heroes.contains(i) &&
          !topBand.contains(i) &&
          i.role != 'underline' &&
          (i.isText || i.isTable),
    )
        .toList();
    if (flow.isEmpty) return;

    // Keep document order (array order = intended reading order).
    // Stable: sort by current Y as a tiebreak so loaded docs behave.
    flow.sort((a, b) => a.position.dy.compareTo(b.position.dy));

    // Group flow items into ROWS: items that are truly side-by-side
    // (vertical overlap AND no x-overlap, e.g. the two signatures).
    final rows = <List<CanvasItem>>[];
    for (final s in flow) {
      final sTop = s.position.dy, sBot = s.position.dy + s.height;
      List<CanvasItem>? hit;
      for (final row in rows) {
        final rTop = row.map((e) => e.position.dy).reduce(math.min);
        final rBot = row.map((e) => e.position.dy + e.height).reduce(math.max);
        final vOverlap = sTop < rBot - 2 && sBot > rTop + 2;
        if (vOverlap && row.every((e) => !xOverlap(s, e))) {
          hit = row;
          break;
        }
      }
      if (hit != null) {
        hit.add(s);
      } else {
        rows.add([s]);
      }
    }

    // Walk rows top-to-bottom, assigning fresh positions with fixed rhythm.
    // - Heroes own page 1 entirely → content starts on page 2.
    // - Top-band items live at the top of page 1 → content starts right
    //   below the lowest top-band bottom edge (with sectionGap breathing room).
    // - Otherwise → content starts at topMargin on page 1.
    double cursor;
    if (heroes.isNotEmpty) {
      cursor = pageH + topMargin;
    } else if (topBand.isNotEmpty) {
      final bandBottom = topBand
          .map((i) => i.position.dy + i.height)
          .reduce(math.max);
      cursor = bandBottom + sectionGap;
    } else {
      cursor = topMargin;
    }

    for (final row in rows) {
      final isHeadingRow = row.length == 1 && row.first.role == 'heading';
      final heading = isHeadingRow ? row.first : null;
      final underline = heading != null ? underlines[heading.group] : null;

      // Height of this block (heading + its underline counts as one unit).
      double blockH;
      if (heading != null) {
        blockH =
            heading.height +
            (underline != null ? headingGap + underline.height : 0);
      } else {
        blockH = row.map((s) => s.height).reduce(math.max);
      }

      // Page-fit: if the block would cross the usable bottom, push to next page.
      // EXCEPTION: single text sections handle their own page-fit via splitting
      // below, so don't pre-push them here.
      final selfPaginates = row.length == 1 &&
          (row.first.isText || row.first.isTable) &&
          row.first.role != 'heading';
      if (!selfPaginates) {
        final pageOfTop = (cursor / pageH).floor();
        final blockBottom = cursor + blockH;
        final pageBottomLimit = pageOfTop * pageH + usableBottom;
        if (blockBottom > pageBottomLimit) {
          cursor = (pageOfTop + 1) * pageH + topMargin;
        }
      }

      // For a heading: make sure its body has room on the SAME page so the
      // heading is never orphaned at the page bottom.
      //  • text body  → it can split, so a few lines below is enough (75).
      //  • table body → tables move as ONE block (no split yet), so require
      //    the WHOLE table to fit. Glues Deliverables/Pricing to their tables
      //    and removes the inconsistent gap.
      if (heading != null) {
        final idx = rows.indexOf(row);
        if (idx + 1 < rows.length) {
          final nextItem = rows[idx + 1].first;
          final pageContentH = usableBottom - topMargin; // a fresh page's room

          double bodyNeeded;
          if (nextItem.isTable) {
            // Option A: heading may start a table if ≥4 rows INCL header fit
            // under it (= header + 3 data rows). If the table is smaller than
            // that, require the whole (small) table. If even this won't fit,
            // the heading drops to the next page WITH its table.
            final trh =
            AutoHeight.measureTableRows(nextItem.tableData!, nextItem.width);
            final hasHdr = nextItem.tableData!.showHeader;
            final dStart = hasHdr ? 1 : 0;
            final dRows = trh.length - dStart;
            double need = hasHdr ? trh[0] : 0;
            final dNeed = dRows < 3 ? dRows : 3;
            for (int i = 0; i < dNeed; i++) {
              need += trh[dStart + i];
            }
            bodyNeeded = need;
          } else {
            bodyNeeded = 110.0; // ~6 lines — keeps a heading off the very bottom
          }

          final wantBottom = cursor + blockH + afterUnderline + bodyNeeded;
          final limit = (cursor / pageH).floor() * pageH + usableBottom;
          debugPrint('📐 HEADING "${heading.title}" @cursor=${cursor.toStringAsFixed(0)} '
              'wantBottom=${wantBottom.toStringAsFixed(0)} limit=${limit.toStringAsFixed(0)} '
              'willDrop=${wantBottom > limit} nextIsTable=${nextItem.isTable}');
          if (wantBottom > limit) {
            cursor = ((cursor / pageH).floor() + 1) * pageH + topMargin;
          }
        }
      }

      // Place the row at `cursor`.
      if (heading != null)
      {
        heading.position = Offset(heading.position.dx, cursor);
        if (underline != null) {
          underline.position = Offset(
            underline.position.dx,
            cursor + heading.height + headingGap,
          );
        }
        cursor +=
            blockH + (underline != null ? afterUnderline : afterHeadingNoRule);
      } else if (row.length == 1 && row.first.isText) {
        // Single text section — flow it across as many pages as needed,
        // reserving the bottom margin on EVERY piece.
        final s = row.first;
        s.overflowSegments = null; // reset any previous split

        final paras = AutoHeight.measureParagraphs(
            s.controller!.document.toDelta().toJson(), s.width);

        // Build a delta-op slice [start, end) from the measured paragraphs.
        List<Map<String, dynamic>> sliceOps(int start, int end) {
          final ops = <Map<String, dynamic>>[];
          for (int i = start; i < end; i++) {
            for (final op in paras[i].ops) {
              ops.add(Map<String, dynamic>.from(op));
            }
            ops.add({'insert': '\n'}); // plain newline between paragraphs
          }
          if (ops.isEmpty) ops.add({'insert': '\n'});
          return ops;
        }

        final segs = <OverflowSegment>[];
        int start = 0;
        bool first = true; // first PLACED piece stays on the section itself
        int guard = 0;

        while (start < paras.length) {
          if (++guard > 300) {
            debugPrint('⚠️ split guard tripped on "${s.title}"');
            break;
          }

          final pageOfCursor = (cursor / pageH).floor();
          final pageBottom = pageOfCursor * pageH + usableBottom;
          final avail = pageBottom - cursor;
          // Reserve the section's own padding PLUS a cushion so text always
          // ends a few px ABOVE the bottom margin (no edge bleed).
          final safeAvail = avail - AutoHeight.textVPad - 8;
          debugPrint('   ↳ "${s.title}" page=$pageOfCursor cursor=${cursor.toStringAsFixed(0)} '
              'pageBottom=${pageBottom.toStringAsFixed(0)} avail=${avail.toStringAsFixed(0)} '
              'safeAvail=${safeAvail.toStringAsFixed(0)}');

          // How many paragraphs from `start` fit in the room we have now?
          double acc = 0;
          int count = 0;
          for (int i = start; i < paras.length; i++) {
            final ph =
                paras[i].height + (i > start ? AutoHeight.paragraphSpacing : 0);
            if (acc + ph > safeAvail) break;
            acc += ph;
            count++;
          }

          final pageTop = pageOfCursor * pageH + topMargin;
          final atPageTop = (cursor - pageTop).abs() < 1;
          final remaining = paras.length - start;

          void place(int from, int to, double h, {required bool isFirst}) {
            if (isFirst) {
              s.position = Offset(s.position.dx, cursor);
              s.height = h;
              s.displayOps = sliceOps(from, to);   // ← ADD THIS LINE
            } else {
              segs.add(OverflowSegment(
                  ops: sliceOps(from, to), y: cursor, height: h));
            }
          }

          if (count >= remaining) {
            final h = acc + AutoHeight.textVPad;
            place(start, paras.length, h, isFirst: first);
            cursor += h + sectionGap;
            start = paras.length;
            first = false;
          } else if (count >= 1 && (!first || acc >= minSplitText)) {
            // Partial piece here, rest flows to the next page.
            final h = acc + AutoHeight.textVPad;
            place(start, start + count, h, isFirst: first);
            start += count;
            cursor = (pageOfCursor + 1) * pageH + topMargin;
            first = false;
          } else if (atPageTop) {
            // Pathological: one paragraph taller than a whole page. Force it
            // so we never loop forever; it will visually overflow but render.
            final h = paras[start].height + AutoHeight.textVPad;
            place(start, start + 1, h, isFirst: first);
            start += 1;
            cursor = (pageOfCursor + 1) * pageH + topMargin;
            first = false;
          } else {
            // Too little room here (e.g. a tiny stub on the first page) →
            // jump to a fresh page and retry. Keep `first` until we place.
            cursor = (pageOfCursor + 1) * pageH + topMargin;
          }
        }

        if (segs.isNotEmpty) {
          s.overflowSegments = segs;
        } else {
          s.displayOps = null; // single piece → render the controller normally
        }
        debugPrint('✂️ FLOW "${s.title}" → ${segs.length + 1} piece(s)');
      } else if (row.length == 1 && row.first.isTable) {
        // Single table — flow across pages. Each piece repeats the header.
        // Splits only where ≥4 rows (incl header) fit; else moves whole.
        final s = row.first;
        s.overflowSegments = null;
        s.displayOps = null;   // ← add
        final td = s.tableData!;
        final rh = AutoHeight.measureTableRows(td, s.width);
        final hasHeader = td.showHeader;
        final headerH = hasHeader ? rh[0] : 0.0;
        final dataStart = hasHeader ? 1 : 0;
        final dataCount = rh.length - dataStart;

        if (dataCount <= 0) {
          s.position = Offset(s.position.dx, cursor);
          cursor += s.height + sectionGap;
        } else {
          final segs = <OverflowSegment>[];
          int start = 0;
          bool first = true;
          int guard = 0;

          double pieceH(int from, int n) {
            double h = headerH;
            for (int i = 0; i < n; i++) {
              h += rh[dataStart + from + i];
            }
            return h + AutoHeight.tableSafety;
          }

          void place(int from, int to, double h, {required bool isFirst}) {
            if (isFirst) {
              s.position = Offset(s.position.dx, cursor);
              s.height = h;
              s.displayTableData = td.copyWith(
                rows: td.rows.sublist(from, to)
                    .map((r) => List<String>.from(r)).toList(),
              );
            } else {
              final slice = td.copyWith(
                rows: td.rows.sublist(from, to)
                    .map((r) => List<String>.from(r)).toList(),
              );
              segs.add(OverflowSegment(tableData: slice, y: cursor, height: h));
            }
          }

          while (start < dataCount) {
            if (++guard > 300) {
              debugPrint('⚠️ table split guard "${s.title}"');
              break;
            }
            final pageOfCursor = (cursor / pageH).floor();
            final pageBottom = pageOfCursor * pageH + usableBottom;
            final avail = pageBottom - cursor;
            final safeAvail = avail - AutoHeight.tableSafety - 8;
            final roomForData = safeAvail - headerH; // header on every piece

            double acc = 0;
            int count = 0;
            for (int i = start; i < dataCount; i++) {
              final r = rh[dataStart + i];
              if (acc + r > roomForData) break;
              acc += r;
              count++;
            }

            final pageTop = pageOfCursor * pageH + topMargin;
            final atPageTop = (cursor - pageTop).abs() < 1;
            final remaining = dataCount - start;
            final rowsInclHeader = count + (hasHeader ? 1 : 0);

            if (count >= remaining) {
              final h = pieceH(start, count);
              place(start, dataCount, h, isFirst: first);
              cursor += h + sectionGap;
              start = dataCount;
              first = false;
            } else if (count >= 1 && rowsInclHeader >= 4) {
              final h = pieceH(start, count);
              place(start, start + count, h, isFirst: first);
              start += count;
              cursor = (pageOfCursor + 1) * pageH + topMargin;
              first = false;
            } else if (atPageTop) {
              // pathological: <4 rows fit even on a fresh page → force ≥1
              final n = count >= 1 ? count : 1;
              final h = pieceH(start, n);
              place(start, start + n, h, isFirst: first);
              start += n;
              cursor = (pageOfCursor + 1) * pageH + topMargin;
              first = false;
            } else {
              // only 2–3 rows fit here → move the whole piece to the next page
              cursor = (pageOfCursor + 1) * pageH + topMargin;
            }
          }

          if (segs.isNotEmpty) {
            s.overflowSegments = segs;
          } else {
            s.displayTableData = null;
          }
          debugPrint('📊 TBL MEASURE "${s.title}" reservedH=${s.height.toStringAsFixed(1)} '
              'rows=${s.tableData?.rowCount} cols=${s.tableData?.columnCount} '
              'width=${s.width.toStringAsFixed(0)} fontSize=${s.tableData?.fontSize}');
          debugPrint('📊 TABLE FLOW "${s.title}" → ${segs.length + 1} piece(s)');
        }
      } else {
        for (final s in row) {
          s.position = Offset(s.position.dx, cursor);
        }
        cursor += blockH + sectionGap;
      }
    }
  }
}
