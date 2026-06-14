// lib/shared/canvas/engine/reflow_engine.dart
//
// Repositions content sections after auto-height so they never overlap.
// Lane-aware (sidebars/main reflow independently), page-break aware (whole
// blocks drop to the next page rather than straddling). Accent rules ride
// with their heading; page backgrounds & sidebars are fixed furniture.
// Mutates items in place. Call autosizeAll() FIRST so heights are correct.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/canvas_item.dart';
import '../../models/canvas_item_type.dart';

class ReflowEngine {
  static const double gap = 12;        // min gap enforced between stacked rows
  static const double topMargin = 50;  // top margin when a block spills to a new page
  static const double topBandTol = 20; // sections within this top-distance = one row

  static void arrange(List<CanvasItem> items, double pageH) {
    if (items.isEmpty) return;

    final content = items.where((i) => i.isText || i.isTable).toList();
    if (content.isEmpty) return;
    final deco = items.where((i) => !(i.isText || i.isTable)).toList();

    bool xOverlap(CanvasItem a, CanvasItem b) =>
        !(a.position.dx + a.width <= b.position.dx ||
            b.position.dx + b.width <= a.position.dx);

    // 1) furniture (never moved): sidebars, page backgrounds, large panels
    bool isFurniture(CanvasItem d) {
      if (d.type == CanvasItemType.rectangle) {
        if (d.height >= 400) return true;
        if (d.width >= 476 && d.height >= 120) return true;
      }
      return false;
    }

    // 2) attach small decorations (accent rules, dividers) to the section above
    final attached = <String, List<_Attached>>{};
    for (final d in deco) {
      if (isFurniture(d)) continue;
      CanvasItem? host;
      double bestTop = -1e9;
      for (final s in content) {
        if (!xOverlap(d, s)) continue;
        final sTop = s.position.dy, sBot = s.position.dy + s.height;
        if (d.position.dy >= sTop - 4 && d.position.dy <= sBot + 16 && sTop > bestTop) {
          bestTop = sTop;
          host = s;
        }
      }
      if (host != null) {
        attached.putIfAbsent(host.id, () => [])
            .add(_Attached(d, d.position.dy - host.position.dy));
      }
    }

    // 3) lanes = connected components of content by x-overlap (union-find)
    final n = content.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int x) { while (parent[x] != x) { parent[x] = parent[parent[x]]; x = parent[x]; } return x; }
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (xOverlap(content[i], content[j])) parent[find(i)] = find(j);
      }
    }
    final lanes = <int, List<CanvasItem>>{};
    for (int i = 0; i < n; i++) {
      lanes.putIfAbsent(find(i), () => []).add(content[i]);
    }

    // 4) reflow each lane
    for (final lane in lanes.values) {
      lane.sort((a, b) => a.position.dy.compareTo(b.position.dy));

      // rows: a section joins a row ONLY if it sits BESIDE the members
      // (vertical overlap but NO x-overlap → true side-by-side, e.g. signatures).
      // If it x-overlaps (same column), it's stacked → its own row → gets pushed.
      final rows = <List<CanvasItem>>[];
      for (final s in lane) {
        final sTop = s.position.dy, sBot = s.position.dy + s.height;
        List<CanvasItem>? hit;
        for (final row in rows) {
          final rTop = row.map((e) => e.position.dy).reduce(math.min);
          final rBot = row.map((e) => e.position.dy + e.height).reduce(math.max);
          final vOverlap = sTop < rBot - 2 && sBot > rTop + 2;
          if (vOverlap && row.every((e) => !xOverlap(s, e))) { hit = row; break; }
        }
        if (hit != null) { hit.add(s); } else { rows.add([s]); }
      }
      rows.sort((a, b) => a.map((e) => e.position.dy).reduce(math.min)
          .compareTo(b.map((e) => e.position.dy).reduce(math.min)));

      double cursor = -1e9;
      for (final row in rows) {
        final rowTop = row.map((s) => s.position.dy).reduce(math.min);
        final rowH = row.map((s) => s.position.dy + s.height).reduce(math.max) - rowTop;
        double newTop = math.max(rowTop, cursor);

        final startPage = (newTop / pageH).floor();
        final endPage = ((newTop + rowH - 1) / pageH).floor();
        if (endPage > startPage) newTop = endPage * pageH + topMargin;

        final delta = newTop - rowTop;
        if (delta.abs() > 0.01) {
          for (final s in row) {
            s.position = Offset(s.position.dx, s.position.dy + delta);
            for (final a in attached[s.id] ?? const <_Attached>[]) {
              a.deco.position = Offset(a.deco.position.dx, s.position.dy + a.offsetY);
            }
          }
        }
        cursor = newTop + rowH + gap;
      }
    }
  }
}

class _Attached {
  final CanvasItem deco;
  final double offsetY;
  _Attached(this.deco, this.offsetY);
}