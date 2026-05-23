// lib/shared/canvas/editor_right_panel.dart
//
// Right sidebar panel for canvas editors.
// Adds: section-type dropdown (text items), AI spellcheck button (page settings).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_fonts.dart';
import '../models/canvas_item.dart';
import '../models/canvas_item_type.dart';
import '../models/section_type.dart';
import 'canvas_controller.dart';
import 'editor_dialogs.dart';
import 'editor_widgets.dart';

class EditorRightPanel extends StatelessWidget {
  final CanvasController ctrl;
  final CanvasItem? selected;
  final bool isMultiSelected;
  final Key toolbarKey;
  final VoidCallback onClose;

  /// Tool-specific content (e.g. AI Fill button) shown below the toolbar.
  final Widget Function(CanvasItem item)? extraContentBuilder;

  /// AI spellcheck button callback (page settings).
  final VoidCallback? onSpellcheck;
  final bool isSpellchecking;

  const EditorRightPanel({
    super.key,
    required this.ctrl,
    required this.selected,
    required this.isMultiSelected,
    required this.toolbarKey,
    required this.onClose,
    this.extraContentBuilder,
    this.onSpellcheck,
    this.isSpellchecking = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 12,
              offset: Offset(-2, 0)),
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
                  if (selected != null && !isMultiSelected)
                    _buildSelectedItemPanel(context, selected!),
                  if (isMultiSelected) _buildMultiSelectPanel(),
                  if (selected == null && !isMultiSelected)
                    _buildPageSettings(context),
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
            'Properties',
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
            child: const Icon(LucideIcons.panelRightClose,
                size: 16, color: AppColors.slateGrey),
          ),
        ],
      ),
    );
  }

  // ─── SELECTED ITEM PANEL ──────────────────────────────────────────────

  Widget _buildSelectedItemPanel(BuildContext context, CanvasItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quill toolbar for text items
        if (item.isText) ...[
          const EditorSectionLabel('TEXT FORMATTING'),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.lavenderBlush,
              borderRadius: BorderRadius.circular(8),
            ),
            child: QuillSimpleToolbar(
              key: toolbarKey,
              controller: item.controller!,
              config: QuillSimpleToolbarConfig(
                toolbarSize: 36,
                buttonOptions: QuillSimpleToolbarButtonOptions(
                  fontFamily: QuillToolbarFontFamilyButtonOptions(
                      items: CanvasController.fontItems),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── SECTION TYPE DROPDOWN ────────────────────────────────
          const EditorSectionLabel('SECTION TYPE'),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.almondSilk),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SectionType>(
                value: item.sectionType,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderRadius: BorderRadius.circular(8),
                icon: const Icon(LucideIcons.chevronDown,
                    size: 16, color: AppColors.slateGrey),
                items: SectionType.values.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Text(
                      t.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: AppFonts.openSans,
                        color: AppColors.prussianBlue,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (t) {
                  if (t != null) ctrl.updateSectionType(t);
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.sectionType.isAutofillable
                ? 'AI can autofill this from your profile'
                : 'Custom — AI will not autofill',
            style: const TextStyle(
              fontSize: 10,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
            ),
          ),
          const SizedBox(height: 12),

          // Extra content slot (e.g. AI Fill button for CV)
          if (extraContentBuilder != null) ...[
            extraContentBuilder!(item),
            const SizedBox(height: 12),
          ],
        ],

        // Item title
        Text(
          item.title.isNotEmpty ? item.title : item.type.name,
          style: const TextStyle(
            color: AppColors.prussianBlue,
            fontSize: 14,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Delete button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              ctrl.saveSnapshot();
              ctrl.deleteSelected();
            },
            icon: const Icon(LucideIcons.trash2,
                size: 14, color: AppColors.error),
            label: const Text('Delete',
                style: TextStyle(color: AppColors.error, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Layer controls
        const EditorSectionLabel('LAYERS'),
        const SizedBox(height: 6),
        Row(
          children: [
            EditorLayerButton(
                icon: LucideIcons.arrowUpToLine,
                tooltip: 'Front',
                onTap: ctrl.bringToFront),
            const SizedBox(width: 4),
            EditorLayerButton(
                icon: LucideIcons.arrowUp,
                tooltip: 'Up',
                onTap: ctrl.bringForward),
            const SizedBox(width: 4),
            EditorLayerButton(
                icon: LucideIcons.arrowDown,
                tooltip: 'Down',
                onTap: ctrl.sendBackward),
            const SizedBox(width: 4),
            EditorLayerButton(
                icon: LucideIcons.arrowDownToLine,
                tooltip: 'Back',
                onTap: ctrl.sendToBack),
          ],
        ),
        const SizedBox(height: 12),

        // Flip (non-text only)
        if (!item.isText) ...[
          const EditorSectionLabel('FLIP'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: EditorActionButton(
                    label: 'Horizontal',
                    icon: LucideIcons.flipHorizontal,
                    onTap: ctrl.flipHorizontal),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: EditorActionButton(
                    label: 'Vertical',
                    icon: LucideIcons.flipVertical,
                    onTap: ctrl.flipVertical),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Fill color
        if (!item.isText &&
            item.type != CanvasItemType.line &&
            item.type != CanvasItemType.icon) ...[
          EditorColorRow(
            label: 'Fill Color',
            color: item.color,
            onTap: () async {
              final c = await EditorDialogs.showColorPicker(
                context: context,
                title: 'Fill Color',
                currentColor: item.color,
              );
              if (c != null) ctrl.updateColor(c);
            },
          ),
          const SizedBox(height: 8),
        ],

        // Border color
        if (!item.isText) ...[
          EditorColorRow(
            label: item.type == CanvasItemType.line
                ? 'Line Color'
                : 'Border Color',
            color: item.borderColor,
            onTap: () async {
              final c = await EditorDialogs.showColorPicker(
                context: context,
                title: item.type == CanvasItemType.line
                    ? 'Line Color'
                    : 'Border Color',
                currentColor: item.borderColor,
              );
              if (c != null) ctrl.updateBorderColor(c);
            },
          ),
          const SizedBox(height: 8),
        ],

        // Border width
        if (!item.isText &&
            item.type != CanvasItemType.imageBox &&
            item.type != CanvasItemType.icon) ...[
          EditorSliderRow(
            label: item.type == CanvasItemType.line ? 'Thickness' : 'Border',
            value: item.borderWidth,
            min: 1,
            max: 12,
            onChanged: (v) => ctrl.updateBorderWidth(v),
          ),
          const SizedBox(height: 8),
        ],

        // Rotation
        if (!item.isText) ...[
          const EditorSectionLabel('ROTATION'),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: (item.rotation * (180 / math.pi)) % 360,
                  min: 0,
                  max: 360,
                  activeColor: AppColors.darkRaspberry,
                  onChanged: (v) =>
                      ctrl.updateRotation(v * (math.pi / 180)),
                  onChangeEnd: (_) => ctrl.saveSnapshot(),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '${((item.rotation * (180 / math.pi)) % 360).toStringAsFixed(0)}°',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkRaspberry,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // Image upload
        if (item.type == CanvasItemType.imageBox) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final result = await FilePicker.pickFiles(
                  type: FileType.image,
                  withData: true,
                );
                if (result != null &&
                    result.files.isNotEmpty &&
                    result.files.first.bytes != null) {
                  ctrl.updateImage(result.files.first.bytes!);
                }
              },
              icon: const Icon(LucideIcons.upload, size: 14),
              label:
              const Text('Upload Image', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Icon picker
        if (item.type == CanvasItemType.icon) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final ic = await EditorDialogs.showIconPicker(
                  context: context,
                  iconColor: item.borderColor,
                );
                if (ic != null) ctrl.updateIcon(ic);
              },
              icon: const Icon(LucideIcons.smile, size: 14),
              label:
              const Text('Change Icon', style: TextStyle(fontSize: 12)),
            ),
          ),
          EditorColorRow(
            label: 'Icon Color',
            color: item.borderColor,
            onTap: () async {
              final c = await EditorDialogs.showColorPicker(
                context: context,
                title: 'Icon Color',
                currentColor: item.borderColor,
              );
              if (c != null) ctrl.updateBorderColor(c);
            },
          ),
        ],
      ],
    );
  }

  // ─── MULTI SELECT PANEL ───────────────────────────────────────────────

  Widget _buildMultiSelectPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Text(
            '${ctrl.multiSelected.length} items selected',
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 13,
              fontFamily: AppFonts.poppins,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ctrl.saveSnapshot();
                ctrl.deleteSelected();
              },
              icon: const Icon(LucideIcons.trash2,
                  size: 14, color: AppColors.error),
              label: const Text('Delete All',
                  style: TextStyle(color: AppColors.error, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PAGE SETTINGS (nothing selected) ─────────────────────────────────

  Widget _buildPageSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EditorSectionLabel('PAGE SETTINGS'),
        const SizedBox(height: 8),
        const Text('Page Size',
            style: TextStyle(
                fontSize: 12,
                fontFamily: AppFonts.openSans,
                color: AppColors.prussianBlue)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.almondSilk),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: 'a4',
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              borderRadius: BorderRadius.circular(8),
              items: const [
                DropdownMenuItem(
                    value: 'a4',
                    child: Text('A4 (595 × 842)',
                        style: TextStyle(fontSize: 12))),
                DropdownMenuItem(
                    value: 'letter',
                    child: Text('Letter (612 × 792)',
                        style: TextStyle(fontSize: 12))),
                DropdownMenuItem(
                    value: 'legal',
                    child: Text('Legal (612 × 1008)',
                        style: TextStyle(fontSize: 12))),
              ],
              onChanged: (v) {},
            ),
          ),
        ),
        const SizedBox(height: 12),
        EditorColorRow(
          label: 'Background',
          color: ctrl.canvasBackground,
          onTap: () async {
            final c = await EditorDialogs.showColorPicker(
              context: context,
              title: 'Canvas Background',
              currentColor: ctrl.canvasBackground,
              enableAlpha: false,
            );
            if (c != null) {
              ctrl.saveSnapshot();
              ctrl.canvasBackground = c;
              ctrl.notify();
            }
          },
        ),
        const SizedBox(height: 16),

        // ── AI SPELLCHECK BUTTON ────────────────────────────────────
        if (onSpellcheck != null) ...[
          const EditorSectionLabel('AI TOOLS'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: isSpellchecking ? null : onSpellcheck,
              icon: isSpellchecking
                  ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              )
                  : const Icon(LucideIcons.spellCheck, size: 16),
              label: Text(
                isSpellchecking ? 'Checking...' : 'AI Spellcheck',
                style: const TextStyle(fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.prussianBlue,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.slateGrey,
                disabledForegroundColor: AppColors.white.withValues(alpha: 0.7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}