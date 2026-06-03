// lib/shared/canvas/canvas_item_widget.dart
//
// Individual canvas item: drag, resize, rotate, flip, text editing.
// NO header bar — text renders at content height (matches picker).
//
// TEXT INTERACTION MODEL:
//   - Single tap  → select (drag mode). Quill NOT focused.
//   - Double tap  → edit mode (Quill focused, can type).
//   - Drag body   → move item (single or multi-select).
//   - Click away  → deselect / exit edit.
//
// MULTI-SELECT MOVE:
//   Controller.multiMoveUpdate() updates all selected items' data positions
//   WITHOUT calling notifyListeners (to avoid killing the drag gesture).
//   The dragged item reads _pos from its data each frame via a manual
//   setState. On pan end, controller.notifyListeners() fires once to sync.

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:kitaura/shared/canvas/engine/shape_painter.dart';
import 'package:kitaura/shared/canvas/engine/snap_guide.dart';
import '../../../core/constants/app_colors.dart';
import '../../models/canvas_item_type.dart';
import '../../models/canvas_item.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class CanvasItemWidget extends StatefulWidget {
  final CanvasItem item;
  final bool isSelected, isMultiSelected;
  final double canvasW, canvasH;
  final VoidCallback onSelect;

  /// Called during multi-select drag with per-frame delta.
  final void Function(Offset delta)? onMultiMoveUpdate;

  /// Called on pan END of multi-select drag.
  final VoidCallback? onMultiMoveEnd;

  final VoidCallback onSaveSnapshot;

  /// All items on the canvas — needed for snap guide calculations.
  final List<CanvasItem> allItems;

  /// Called with guide lines during drag (or empty list when drag ends).
  final void Function(List<GuideLine>)? onSnapGuidesChanged;

  const CanvasItemWidget({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isMultiSelected,
    required this.canvasW,
    required this.canvasH,
    required this.onSelect,
    required this.onSaveSnapshot,
    required this.allItems,
    this.onMultiMoveUpdate,
    this.onMultiMoveEnd,
    this.onSnapGuidesChanged,
  });

  @override
  State<CanvasItemWidget> createState() => _CanvasItemWidgetState();
}

class _CanvasItemWidgetState extends State<CanvasItemWidget> {
  late Offset _pos;
  late double _w, _h;
  Offset _dragStart = Offset.zero, _posAtDragStart = Offset.zero;
  double _wAtResize = 0, _hAtResize = 0;
  Offset _resizeOrigin = Offset.zero;
  ResizeHandle? _activeHandle;

  bool _editMode = false;
  bool _isDraggingSolo = false;

  @override
  void initState() {
    super.initState();
    _pos = widget.item.position;
    _w = widget.item.width;
    _h = widget.item.height;
  }

  @override
  void didUpdateWidget(CanvasItemWidget old) {
    super.didUpdateWidget(old);
    // Always sync from data unless mid-solo-drag
    if (!_isDraggingSolo) {
      _pos = widget.item.position;
      _w = widget.item.width;
      _h = widget.item.height;
    }
    if (!widget.isSelected && _editMode) {
      _editMode = false;
      widget.item.focusNode?.unfocus();
    }
  }

  void _commit() {
    widget.item.position = _pos;
    widget.item.width = _w;
    widget.item.height = _h;
  }

  // ── DRAG ──────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d) {
    widget.onSelect();
    widget.onSaveSnapshot();
    _dragStart = d.globalPosition;
    _posAtDragStart = _pos;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (widget.onMultiMoveUpdate != null) {
      // MULTI-SELECT: controller updates ALL items silently.
      widget.onMultiMoveUpdate!(d.delta);
      setState(() { _pos = widget.item.position; });
      return;
    }

    // SOLO DRAG with snap guides
    _isDraggingSolo = true;
    final delta = d.globalPosition - _dragStart;
    // canvasH includes page gaps (24px between pages), but item positions
    // don't include gaps. Subtract gaps from clamp max to keep items in pages.
    const pageGap = 24.0;
    const pageH = 842.0;
    final totalPages = (widget.canvasH / (pageH + pageGap)).ceil().clamp(1, 99);
    final usableH = pageH * totalPages; // total without gaps
    final rawPos = Offset(
      (_posAtDragStart.dx + delta.dx).clamp(0, widget.canvasW - _w),
      (_posAtDragStart.dy + delta.dy).clamp(0, usableH - _h),
    );

    // Calculate snap
    final snap = SnapGuide.calculate(
      dragPos: rawPos,
      dragW: _w,
      dragH: _h,
      dragId: widget.item.id,
      allItems: widget.allItems,
      canvasW: widget.canvasW,
      canvasH: widget.canvasH,
    );

    setState(() { _pos = snap.snappedPosition; });
    widget.onSnapGuidesChanged?.call(snap.guides);
  }

  void _onDragEnd(DragEndDetails _) {
    // Clear snap guides
    widget.onSnapGuidesChanged?.call([]);

    if (widget.onMultiMoveUpdate != null) {
      widget.onMultiMoveEnd?.call();
    } else {
      _isDraggingSolo = false;
      _commit();
    }
  }

  // ── RESIZE ────────────────────────────────────────────────────────

  void _onResizeUpdate(ResizeHandle handle, Offset delta) {
    double l = _posAtDragStart.dx, t = _posAtDragStart.dy;
    double r = l + _wAtResize, b = t + _hAtResize;
    final dx = delta.dx, dy = delta.dy;
    switch (handle) {
      case ResizeHandle.topLeft:     l += dx; t += dy;
      case ResizeHandle.top:         t += dy;
      case ResizeHandle.topRight:    r += dx; t += dy;
      case ResizeHandle.right:       r += dx;
      case ResizeHandle.bottomRight: r += dx; b += dy;
      case ResizeHandle.bottom:      b += dy;
      case ResizeHandle.bottomLeft:  l += dx; b += dy;
      case ResizeHandle.left:        l += dx;
    }
    const minW = 40.0, minH = 20.0;
    if (r - l < minW) {
      if (handle.name.contains('Left')) {
        l = r - minW;
      } else {
        r = l + minW;
      }
    }
    if (b - t < minH) {
      if (handle.name.contains('top')) {
        t = b - minH;
      } else {
        b = t + minH;
      }
    }
    const pageGap = 24.0;
    const pageH = 842.0;
    final totalPages = (widget.canvasH / (pageH + pageGap)).ceil().clamp(1, 99);
    final usableH = pageH * totalPages.toDouble();
    setState(() {
      _pos = Offset(
        l.clamp(0, widget.canvasW - minW),
        t.clamp(0, usableH - minH),
      );
      _w = (r - l).clamp(minW, widget.canvasW - _pos.dx);
      _h = (b - t).clamp(minH, usableH - _pos.dy);
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Calculate which page this item belongs to and add visual gap
    const pageGap = 24.0;
    const canvasH = 842.0;
    final pageIdx = (_pos.dy / canvasH).floor();
    final renderTop = _pos.dy + (pageIdx * pageGap);

    return Positioned(
      left: _pos.dx,
      top: renderTop,
      width: _w,
      height: _h,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(widget.item.rotation)
          ..scaleByVector3(Vector3(
            widget.item.flipX ? -1.0 : 1.0,
            widget.item.flipY ? -1.0 : 1.0,
            1.0,
          )),
        child: Stack(clipBehavior: Clip.none, children: [
          _buildBody(),
          if (widget.isSelected || widget.isMultiSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: widget.isMultiSelected
                          ? Colors.orange
                          : (_editMode
                          ? AppColors.magentaBloom
                          : AppColors.darkRaspberry),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          if (widget.isSelected && !_editMode) ..._buildResizeHandles(),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.item.isText) {
      if (_editMode) {
        return Container(
          color: Colors.transparent,
          child: QuillEditor(
            controller: widget.item.controller!,
            focusNode: widget.item.focusNode!,
            scrollController: widget.item.scrollController!,
            config: QuillEditorConfig(
              scrollable: true, expands: false, autoFocus: true,
              padding: EdgeInsets.zero, placeholder: widget.item.title,
              customStyleBuilder: _styleBuilder,
            ),
          ),
        );
      }

      return MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () { if (!widget.isSelected) widget.onSelect(); },
          onDoubleTap: () {
            widget.onSelect();
            setState(() => _editMode = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.item.focusNode?.requestFocus();
            });
          },
          onPanStart: _onDragStart,
          onPanUpdate: _onDragUpdate,
          onPanEnd: _onDragEnd,
          child: AbsorbPointer(
            child: QuillEditor(
              controller: widget.item.controller!,
              focusNode: widget.item.focusNode!,
              scrollController: widget.item.scrollController!,
              config: QuillEditorConfig(
                scrollable: false, expands: false, autoFocus: false,
                padding: EdgeInsets.zero, placeholder: widget.item.title,
                customStyleBuilder: _styleBuilder,
              ),
            ),
          ),
        ),
      );
    }

    // Non-text items
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        onPanStart: _onDragStart,
        onPanUpdate: _onDragUpdate,
        onPanEnd: _onDragEnd,
        child: _buildShapeBody(),
      ),
    );
  }

  TextStyle _styleBuilder(Attribute attribute) {
    if (attribute.key == Attribute.font.key) {
      final family = attribute.value as String?;
      if (family != null) return TextStyle(fontFamily: family);
    }
    return const TextStyle();
  }

  Widget _buildShapeBody() {
    final vertices = shapeVertices(widget.item.type);
    if (vertices.isNotEmpty) {
      return SizedBox.expand(
        child: CustomPaint(
          painter: ShapePainter(
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
          color: widget.item.borderColor,
        );
      case CanvasItemType.rectangle:
        return Container(
          decoration: BoxDecoration(
            color: widget.item.color,
            border: Border.all(color: widget.item.borderColor, width: widget.item.borderWidth),
          ),
        );
      case CanvasItemType.circle:
        return Container(
          decoration: BoxDecoration(
            color: widget.item.color, shape: BoxShape.circle,
            border: Border.all(color: widget.item.borderColor, width: widget.item.borderWidth),
          ),
        );
      case CanvasItemType.imageBox:
        return Container(
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
              Text('Upload Image', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        );
      case CanvasItemType.icon:
        return Center(
          child: Icon(widget.item.iconData ?? Icons.star, size: _w * 0.7, color: widget.item.borderColor),
        );
      default:
        return const SizedBox();
    }
  }

  List<Widget> _buildResizeHandles() {
    const hit = 24.0, vis = 10.0, h = hit / 2;
    final handles = {
      ResizeHandle.topLeft: Offset(-h, -h),
      ResizeHandle.top: Offset(_w / 2 - h, -h),
      ResizeHandle.topRight: Offset(_w - h, -h),
      ResizeHandle.right: Offset(_w - h, _h / 2 - h),
      ResizeHandle.bottomRight: Offset(_w - h, _h - h),
      ResizeHandle.bottom: Offset(_w / 2 - h, _h - h),
      ResizeHandle.bottomLeft: Offset(-h, _h - h),
      ResizeHandle.left: Offset(-h, _h / 2 - h),
    };
    final cursors = {
      ResizeHandle.topLeft: SystemMouseCursors.resizeUpLeft,
      ResizeHandle.top: SystemMouseCursors.resizeUp,
      ResizeHandle.topRight: SystemMouseCursors.resizeUpRight,
      ResizeHandle.right: SystemMouseCursors.resizeRight,
      ResizeHandle.bottomRight: SystemMouseCursors.resizeDownRight,
      ResizeHandle.bottom: SystemMouseCursors.resizeDown,
      ResizeHandle.bottomLeft: SystemMouseCursors.resizeDownLeft,
      ResizeHandle.left: SystemMouseCursors.resizeLeft,
    };
    return handles.entries.map((e) {
      final handle = e.key;
      return Positioned(
        left: e.value.dx,
        top: e.value.dy,
        child: MouseRegion(
          cursor: cursors[handle]!,
          child: GestureDetector(
            onPanStart: (d) {
              _activeHandle = handle;
              widget.onSaveSnapshot();
              _resizeOrigin = d.globalPosition;
              _posAtDragStart = _pos;
              _wAtResize = _w;
              _hAtResize = _h;
            },
            onPanUpdate: (d) {
              if (_activeHandle != handle) return;
              _onResizeUpdate(handle, d.globalPosition - _resizeOrigin);
            },
            onPanEnd: (_) {
              _activeHandle = null;
              _commit();
            },
            child: SizedBox(
              width: hit, height: hit,
              child: Center(
                child: Container(
                  width: vis, height: vis,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.darkRaspberry, width: 1.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}