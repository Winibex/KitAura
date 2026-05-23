import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'canvas_item_type.dart';
import 'section_type.dart';

// ─── CANVAS ITEM MODEL ───────────────────────────────────────────────────

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

  /// What kind of CV section this is (for AI autofill). Only meaningful
  /// for textSection items. Auto-detected from title if not provided.
  SectionType sectionType;

  QuillController? controller;
  FocusNode? focusNode;
  ScrollController? scrollController;

  CanvasItem({
    required this.type,
    required this.position,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.color = Colors.transparent,
    this.borderColor = Colors.grey,
    this.borderWidth = 1,
    this.imageBytes,
    this.iconData,
    this.title = '',
    this.flipX = false,
    this.flipY = false,
    SectionType? sectionType,
  })  : id = UniqueKey().toString(),
  // Auto-detect from title if caller didn't specify
        sectionType = sectionType ??
            (type == CanvasItemType.textSection
                ? SectionType.detectFromTitle(title)
                : SectionType.custom) {
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

// ─── SNAPSHOT (for undo/redo) ────────────────────────────────────────────

class ItemSnapshot {
  final String id;
  final CanvasItemType type;
  final Offset position;
  final double width, height, rotation, borderWidth;
  final Color color, borderColor;
  final IconData? iconData;
  final String title;
  final bool flipX, flipY;
  final SectionType sectionType;

  ItemSnapshot({
    required this.id,
    required this.type,
    required this.position,
    required this.width,
    required this.height,
    required this.rotation,
    required this.borderWidth,
    required this.color,
    required this.borderColor,
    required this.iconData,
    required this.title,
    required this.flipX,
    required this.flipY,
    required this.sectionType,
  });

  factory ItemSnapshot.from(CanvasItem item) => ItemSnapshot(
    id: item.id,
    type: item.type,
    position: item.position,
    width: item.width,
    height: item.height,
    rotation: item.rotation,
    borderWidth: item.borderWidth,
    color: item.color,
    borderColor: item.borderColor,
    iconData: item.iconData,
    title: item.title,
    flipX: item.flipX,
    flipY: item.flipY,
    sectionType: item.sectionType,
  );
}

class CanvasSnapshot {
  final List<ItemSnapshot> items;
  final String? selectedId;
  final Color canvasBackground;

  CanvasSnapshot(this.items, this.selectedId, this.canvasBackground);
}