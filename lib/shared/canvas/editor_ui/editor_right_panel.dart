// lib/shared/canvas/editor_right_panel.dart
//
// Right sidebar panel for canvas editors.
// Adds: section-type dropdown (text items), AI spellcheck button (page settings).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../models/canvas_item.dart';
import '../../models/canvas_item_type.dart';
import '../../models/section_type.dart';
import '../engine/canvas_controller.dart';
import 'editor_dialogs.dart';
import 'editor_widgets.dart';

class EditorRightPanel extends StatefulWidget {
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

  final Future<void> Function(CanvasItem item, String mode, String? customInstruction)? onRewrite;

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
    this.onRewrite,  // NEW
  });
  @override
  State<EditorRightPanel> createState() => _EditorRightPanelState();
}
class _EditorRightPanelState extends State<EditorRightPanel> {
  String _rewriteMode = 'professional';
  final _rewriteInstructionCtrl = TextEditingController();
  bool _isRewriting = false;

  @override
  void dispose() {
    _rewriteInstructionCtrl.dispose();
    super.dispose();
  }

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
                  if (widget.selected != null && !widget.isMultiSelected)
                    _buildSelectedItemPanel(context, widget.selected!),
                  if (widget.isMultiSelected) _buildMultiSelectPanel(),
                  if (widget.selected == null && !widget.isMultiSelected)
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
            onTap: widget.onClose,
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
              key: widget.toolbarKey,
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
                  if (t != null) widget.ctrl.updateSectionType(t);
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
          if (widget.extraContentBuilder != null) ...[
            widget.extraContentBuilder!(item),
            const SizedBox(height: 12),
          ],

          // ── AI REWRITE SECTION ──────────────────────────────────
          if (widget.onRewrite != null) ...[
            const Divider(color: AppColors.almondSilk),
            const SizedBox(height: 8),
            const EditorSectionLabel('AI REWRITE'),
            const SizedBox(height: 6),
            // Mode dropdown
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.almondSilk),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _rewriteMode,
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  borderRadius: BorderRadius.circular(8),
                  icon: const Icon(LucideIcons.chevronDown,
                      size: 16, color: AppColors.slateGrey),
                  items: const [
                    DropdownMenuItem(value: 'professional', child: Text('Professional', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'concise', child: Text('Concise', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'detailed', child: Text('Detailed', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'creative', child: Text('Creative', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => setState(() => _rewriteMode = v ?? 'professional'),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Custom instruction
            TextField(
              controller: _rewriteInstructionCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, fontFamily: AppFonts.openSans),
              decoration: InputDecoration(
                hintText: 'Custom instruction (optional)...\ne.g. "focus on metrics"',
                hintStyle: const TextStyle(color: AppColors.slateGrey, fontSize: 10),
                contentPadding: const EdgeInsets.all(8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.almondSilk),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.almondSilk),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.darkRaspberry),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Rewrite button
            SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton.icon(
                onPressed: _isRewriting ? null : () async {
                  setState(() => _isRewriting = true);
                  await widget.onRewrite!(
                    item,
                    _rewriteMode,
                    _rewriteInstructionCtrl.text.trim().isEmpty
                        ? null
                        : _rewriteInstructionCtrl.text.trim(),
                  );
                  if (mounted) setState(() => _isRewriting = false);
                },
                icon: _isRewriting
                    ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                    : Icon(LucideIcons.pencil, size: 14),
                label: Text(
                  _isRewriting ? 'Rewriting...' : 'AI Rewrite — ${item.title}',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRewriting ? AppColors.slateGrey : const Color(0xFFA36D90),
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── TEXT CLIPBOARD (copy/paste with formatting) ─────────
          const EditorSectionLabel('TEXT CLIPBOARD'),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    widget.ctrl.copySelectedText();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Text copied with formatting'), duration: Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(LucideIcons.copy, size: 12, color: AppColors.prussianBlue),
                  label: const Text('Copy Text', style: TextStyle(color: AppColors.prussianBlue, fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.almondSilk),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.ctrl.hasClipboardDelta
                      ? () { widget.ctrl.pasteFormattedText(); setState(() {}); }
                      : null,
                  icon: Icon(LucideIcons.clipboardPaste, size: 12,
                      color: widget.ctrl.hasClipboardDelta ? AppColors.prussianBlue : AppColors.slateGrey),
                  label: Text('Paste Text',
                      style: TextStyle(
                          color: widget.ctrl.hasClipboardDelta ? AppColors.prussianBlue : AppColors.slateGrey,
                          fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: widget.ctrl.hasClipboardDelta ? AppColors.almondSilk : AppColors.petalFrost),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

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

        // Duplicate button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.ctrl.duplicateSelected,
            icon: const Icon(LucideIcons.copy, size: 14, color: AppColors.prussianBlue),
            label: const Text('Duplicate',
                style: TextStyle(color: AppColors.prussianBlue, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.almondSilk),
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Delete button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              widget.ctrl.saveSnapshot();
              widget.ctrl.deleteSelected();
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
                onTap: widget.ctrl.bringToFront),
            const SizedBox(width: 4),
            EditorLayerButton(
                icon: LucideIcons.arrowUp,
                tooltip: 'Up',
                onTap: widget.ctrl.bringForward),
            const SizedBox(width: 4),
            EditorLayerButton(
                icon: LucideIcons.arrowDown,
                tooltip: 'Down',
                onTap: widget.ctrl.sendBackward),
            const SizedBox(width: 4),
            EditorLayerButton(
                icon: LucideIcons.arrowDownToLine,
                tooltip: 'Back',
                onTap: widget.ctrl.sendToBack),
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
                    onTap: widget.ctrl.flipHorizontal),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: EditorActionButton(
                    label: 'Vertical',
                    icon: LucideIcons.flipVertical,
                    onTap: widget.ctrl.flipVertical),
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
              if (c != null) widget.ctrl.updateColor(c);
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
              if (c != null) widget.ctrl.updateBorderColor(c);
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
            onChanged: (v) => widget.ctrl.updateBorderWidth(v),
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
                      widget.ctrl.updateRotation(v * (math.pi / 180)),
                  onChangeEnd: (_) => widget.ctrl.saveSnapshot(),
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
                  widget.ctrl.updateImage(result.files.first.bytes!);
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
                if (ic != null) widget.ctrl.updateIcon(ic);
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
              if (c != null) widget.ctrl.updateBorderColor(c);
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
            '${widget.ctrl.multiSelected.length} items selected',
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
                widget.ctrl.saveSnapshot();
                widget.ctrl.deleteSelected();
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

  // ─── PAGE SETTINGS (nothing widget.selected) ─────────────────────────────────

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
          color: widget.ctrl.canvasBackground,
          onTap: () async {
            final c = await EditorDialogs.showColorPicker(
              context: context,
              title: 'Canvas Background',
              currentColor: widget.ctrl.canvasBackground,
              enableAlpha: false,
            );
            if (c != null) {
              widget.ctrl.saveSnapshot();
              widget.ctrl.canvasBackground = c;
              widget.ctrl.notify();
            }
          },
        ),
        const SizedBox(height: 16),

        // ── AI SPELLCHECK BUTTON ────────────────────────────────────
        if (widget.onSpellcheck != null) ...[
          const EditorSectionLabel('AI TOOLS'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: widget.isSpellchecking ? null : widget.onSpellcheck,
              icon: widget.isSpellchecking
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
                widget.isSpellchecking ? 'Checking...' : 'AI Spellcheck',
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
