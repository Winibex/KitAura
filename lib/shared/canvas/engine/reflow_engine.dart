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
  static const double minSplitText = 70; // ~4-5 lines; below this, don't split

  static void arrange(List<CanvasItem> items, double pageH) {
    if (items.isEmpty) return;

    debugPrint('🔧 REFLOW: ${items.length} items | '
        'heroes=${items.where((i) => i.role == "hero").length} | '
        'headings=${items.where((i) => i.role == "heading").length} | '
        'underlines=${items.where((i) => i.role == "underline").length}');

    final usableBottom = pageH - bottomMargin;

    bool xOverlap(CanvasItem a, CanvasItem b) =>
        !(a.position.dx + a.width <= b.position.dx ||
            b.position.dx + b.width <= a.position.dx);

    // Hero items: pinned, never moved, not part of flow.
    final heroes = items.where((i) => i.role == 'hero').toSet();

    // Underlines are positioned relative to their heading, not flowed alone.
    final underlines = <String, CanvasItem>{}; // group -> underline
    for (final i in items) {
      if (i.role == 'underline' && i.group != null) underlines[i.group!] = i;
    }

    // Flowing content = text/table that isn't hero and isn't an underline.
    final flow = items
        .where(
          (i) =>
              !heroes.contains(i) &&
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
    // If hero items exist, they own page 1 — content starts on page 2.
    double cursor = heroes.isNotEmpty ? pageH + topMargin : topMargin;

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
      final isSplittableText = row.length == 1 &&
          row.first.isText &&
          row.first.role != 'heading';
      if (!isSplittableText) {
        final pageOfTop = (cursor / pageH).floor();
        final blockBottom = cursor + blockH;
        final pageBottomLimit = pageOfTop * pageH + usableBottom;
        if (blockBottom > pageBottomLimit) {
          cursor = (pageOfTop + 1) * pageH + topMargin;
        }
      }

      // For a heading: also make sure the NEXT row (its body) has room on the
      // same page — prevents an orphaned heading at the page bottom.
      if (heading != null) {
        final idx = rows.indexOf(row);
        if (idx + 1 < rows.length) {
          final next = rows[idx + 1];
          final nextItem = next.first;
          final minBody = nextItem.isTable ? 90.0 : 75.0;
          final wantBottom = cursor + blockH + afterUnderline + minBody;
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
      if (heading != null) {
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
        // Single text section — may need to split across the page boundary.
        final s = row.first;
        s.overflowOps = null; // reset any previous split

        debugPrint('🔎 ENTER TEXT "${s.title}" pos.dy=${s.position.dy.toStringAsFixed(0)} '
            'cursor=${cursor.toStringAsFixed(0)} h=${s.height.toStringAsFixed(0)}');

        final pageOfTop = (cursor / pageH).floor();
        final pageBottom = pageOfTop * pageH + usableBottom;
        final fitsHere = cursor + s.height <= pageBottom;
        debugPrint('📄 TEXT "${s.title}" h=${s.height.toStringAsFixed(0)} '
            '@cursor=${cursor.toStringAsFixed(0)} pageBottom=${pageBottom.toStringAsFixed(0)} '
            'fitsHere=$fitsHere');

        if (fitsHere) {
          s.position = Offset(s.position.dx, cursor);
          cursor += s.height + sectionGap;
        } else {
          // Measure paragraphs to find how many fit before pageBottom.
          final paras = AutoHeight.measureParagraphs(
              s.controller!.document.toDelta().toJson(), s.width);
          final avail = pageBottom - cursor;

          final safeAvail = avail - 10; // small cushion so text doesn't kiss margin
          double acc = 0;
          int fitCount = 0;
          for (int i = 0; i < paras.length; i++) {
            final ph = paras[i].height +
                (i > 0 ? AutoHeight.paragraphSpacing : 0);
            if (acc + ph > safeAvail) break;
            acc += ph;
            fitCount++;
          }

          if (acc >= minSplitText && fitCount >= 1 && fitCount < paras.length) {
            debugPrint('✂️ SPLIT "${s.title}" acc=${acc.toStringAsFixed(0)} '
                'fitCount=$fitCount/${paras.length}');
            final (firstOps, secondOps) =
            AutoHeight.splitParagraphs(paras, fitCount);
            s.position = Offset(s.position.dx, cursor);
            s.height = acc + AutoHeight.textVPad;
            s.overflowOps = secondOps;
            // Continuation goes to top of next page.
            final contY = (pageOfTop + 1) * pageH + topMargin;
            s.overflowY = contY;                    // ← record it
            final contH = AutoHeight.measureText(secondOps, s.width);
            cursor = contY + contH + sectionGap;
          } else {
            // Can't fit even one paragraph → push whole section to next page.
            cursor = (pageOfTop + 1) * pageH + topMargin;
            s.position = Offset(s.position.dx, cursor);
            cursor += s.height + sectionGap;
          }
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
