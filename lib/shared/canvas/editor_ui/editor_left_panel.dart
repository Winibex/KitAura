// lib/shared/canvas/editor_left_panel.dart
//
// Left sidebar panel for canvas editors (CV, Proposal).
// Contains: add elements grid, global text controls, layers list.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../models/canvas_item_type.dart';
import '../engine/canvas_controller.dart';
import 'editor_widgets.dart';

class EditorLeftPanel extends StatelessWidget {
  final CanvasController ctrl;
  final VoidCallback onClose;
  final VoidCallback onAddText;

  const EditorLeftPanel({
    super.key,
    required this.ctrl,
    required this.onClose,
    required this.onAddText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 12,
              offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAddElements(),
                  const SizedBox(height: 12),
                  if (ctrl.items.any((i) => i.isText)) ...[
                    _buildGlobalTextControls(),
                    const SizedBox(height: 12),
                  ],
                  _buildLayersList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.petalFrost)),
      ),
      child: Row(
        children: [
          const Text(
            'Toolbar',
            style: TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 13,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: const Icon(LucideIcons.panelLeftClose,
                size: 16, color: AppColors.slateGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildAddElements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EditorSectionLabel('ADD ELEMENTS'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            EditorAddButton(label: 'Text', icon: LucideIcons.type, onTap: onAddText),
            EditorAddButton(label: 'Line', icon: LucideIcons.minus, onTap: () => ctrl.addShape(CanvasItemType.line)),
            EditorAddButton(label: 'Rect', icon: LucideIcons.square, onTap: () => ctrl.addShape(CanvasItemType.rectangle)),
            EditorAddButton(label: 'Circle', icon: LucideIcons.circle, onTap: () => ctrl.addShape(CanvasItemType.circle)),
            EditorAddButton(label: 'Image', icon: LucideIcons.image, onTap: () => ctrl.addShape(CanvasItemType.imageBox)),
            EditorAddButton(label: 'Icon', icon: LucideIcons.smile, onTap: () => ctrl.addShape(CanvasItemType.icon)),
            EditorAddButton(label: 'Triangle', icon: LucideIcons.triangle, onTap: () => ctrl.addShape(CanvasItemType.triangle)),
            EditorAddButton(label: 'Star', icon: LucideIcons.star, onTap: () => ctrl.addShape(CanvasItemType.star)),
            EditorAddButton(label: 'Arrow', icon: LucideIcons.arrowRight, onTap: () => ctrl.addShape(CanvasItemType.arrow)),
            EditorAddButton(label: 'Diamond', icon: LucideIcons.diamond, onTap: () => ctrl.addShape(CanvasItemType.diamond)),
            EditorAddButton(label: 'Hexagon', icon: LucideIcons.hexagon, onTap: () => ctrl.addShape(CanvasItemType.hexagon)),
          ],
        ),
      ],
    );
  }

  Widget _buildGlobalTextControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EditorSectionLabel('GLOBAL TEXT'),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('Font',
                style: TextStyle(fontSize: 11, fontFamily: AppFonts.openSans, color: AppColors.prussianBlue)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String>(
                value: ctrl.globalFont,
                isExpanded: true,
                isDense: true,
                items: CanvasController.fontItems.entries
                    .map((e) => DropdownMenuItem(
                  value: e.value,
                  child: Text(e.key, style: const TextStyle(fontSize: 12)),
                ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) ctrl.applyGlobalFont(v);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('Size',
                style: TextStyle(fontSize: 11, fontFamily: AppFonts.openSans, color: AppColors.prussianBlue)),
            const SizedBox(width: 8),
            DropdownButton<double>(
              value: ctrl.globalFontSize,
              isDense: true,
              items: [10, 11, 12, 13, 14, 16, 18, 20, 24]
                  .map((s) => DropdownMenuItem(
                value: s.toDouble(),
                child: Text('$s', style: const TextStyle(fontSize: 12)),
              ))
                  .toList(),
              onChanged: (v) {
                if (v != null) ctrl.applyGlobalFontSize(v);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLayersList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EditorSectionLabel('LAYERS'),
        const SizedBox(height: 6),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ctrl.items.length,
          onReorder: ctrl.reorder,
          itemBuilder: (ctx, idx) {
            final item = ctrl.items[ctrl.items.length - 1 - idx];
            final isSel = item.id == ctrl.selectedId ||
                ctrl.multiSelected.contains(item.id);
            return ListTile(
              key: ValueKey(item.id),
              dense: true,
              visualDensity: const VisualDensity(vertical: -3),
              selected: isSel,
              selectedTileColor: AppColors.petalFrost,
              leading: Icon(
                canvasItemTypeIcon(item.type),
                size: 14,
                color: isSel ? AppColors.darkRaspberry : AppColors.slateGrey,
              ),
              title: Text(
                item.title.isNotEmpty ? item.title : item.type.name,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: AppFonts.poppins,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                  color: isSel ? AppColors.darkRaspberry : AppColors.prussianBlue,
                ),
              ),
              onTap: () => ctrl.select(item.id),
            );
          },
        ),
      ],
    );
  }
}