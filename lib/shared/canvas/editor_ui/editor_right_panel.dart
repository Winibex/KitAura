// lib/shared/canvas/editor_ui/editor_right_panel.dart
//
// Right sidebar panel for canvas editors (CV / Cover Letter / Proposal).
// Section visibility is driven by EditorPanelConfig.
//
// PHASE D REDESIGN:
//   - AI Tools block has two modes:
//       * Selected text item → per-section Compose + Refine + Section Type
//       * Nothing selected → All-Sections Compose (CV editor only)
//   - Section Type uses the same pill style as the Career Profile selector
//   - Bottom-of-panel "SECTION TYPE" section removed (moved into AI block)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/constants/app_ai_labels.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../models/canvas_item.dart';
import '../../models/canvas_item_type.dart';
import '../../models/section_type.dart';
import '../../providers/feature_flags_provider.dart';
import '../engine/canvas_controller.dart';
import 'editor_dialogs.dart';
import 'editor_panel_config.dart';
import 'editor_widgets.dart';

typedef PickCareerProfileCallback = Future<String?> Function();

typedef AiComposeCallback =
    Future<void> Function(CanvasItem item, {required bool useAi});

typedef AiComposeAllCallback = Future<void> Function({required bool useAi});

class EditorRightPanel extends ConsumerStatefulWidget {
  final CanvasController ctrl;
  final CanvasItem? selected;
  final bool isMultiSelected;
  final Key toolbarKey;
  final VoidCallback onClose;
  final EditorPanelConfig config;
  final Widget Function(CanvasItem item)? extraContentBuilder;
  final VoidCallback? onSpellcheck;
  final bool isSpellchecking;
  final Future<void> Function(
    CanvasItem item,
    String mode,
    String? customInstruction,
  )?
  onRefine;
  final AiComposeCallback? onCompose;
  final AiComposeAllCallback? onComposeAll;
  final bool isComposing;
  final bool isRefining;
  final String? selectedProfileName;
  final PickCareerProfileCallback? onPickCareerProfile;

  const EditorRightPanel({
    super.key,
    required this.ctrl,
    required this.selected,
    required this.isMultiSelected,
    required this.toolbarKey,
    required this.onClose,
    this.config = const EditorPanelConfig(),
    this.extraContentBuilder,
    this.onSpellcheck,
    this.isSpellchecking = false,
    this.onRefine,
    this.onCompose,
    this.onComposeAll,
    this.isComposing = false,
    this.isRefining = false,
    this.selectedProfileName,
    this.onPickCareerProfile,
  });

  @override
  ConsumerState<EditorRightPanel> createState() => _EditorRightPanelState();
}

class _EditorRightPanelState extends ConsumerState<EditorRightPanel> {
  String? _activeCustomMode;
  final _customInstructionCtrl = TextEditingController();

  bool get _aiComposeEnabled =>
      ref.watch(featureFlagsProvider).value?.aiComposeEnabled ?? true;
  bool get _aiRefineEnabled =>
      ref.watch(featureFlagsProvider).value?.aiRefineEnabled ?? true;
  bool get _aiProofreadEnabled =>
      ref.watch(featureFlagsProvider).value?.aiProofreadEnabled ?? true;

  @override
  void dispose() {
    _customInstructionCtrl.dispose();
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
            offset: Offset(-2, 0),
          ),
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
            child: const Icon(
              LucideIcons.panelRightClose,
              size: 16,
              color: AppColors.slateGrey,
            ),
          ),
        ],
      ),
    );
  }

  // ── SELECTED ITEM PANEL ─────────────────────────────────────────

  Widget _buildSelectedItemPanel(BuildContext context, CanvasItem item) {
    final isText = item.isText;
    final composeAvailable =
        widget.config.showAiCompose && widget.onCompose != null && _aiComposeEnabled;
    final refineAvailable =
        widget.config.showAiRefine && widget.onRefine != null && _aiRefineEnabled;
    final showAiBlock = isText && (composeAvailable || refineAvailable);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAiBlock) ...[
          _buildAiToolsForSelected(item),
          const SizedBox(height: 14),
        ],
        if (isText) ...[
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
                    items: CanvasController.fontItems,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const EditorSectionLabel('TEXT CLIPBOARD'),
          const SizedBox(height: 4),
          _buildTextClipboardRow(context),
          const SizedBox(height: 12),
        ],
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
        if (widget.config.showDuplicate) ...[
          _buildOutlinedButton(
            label: 'Duplicate',
            icon: LucideIcons.copy,
            color: AppColors.prussianBlue,
            onTap: widget.ctrl.duplicateSelected,
          ),
          const SizedBox(height: 8),
        ],
        _buildOutlinedButton(
          label: 'Delete',
          icon: LucideIcons.trash2,
          color: AppColors.error,
          onTap: () {
            widget.ctrl.saveSnapshot();
            widget.ctrl.deleteSelected();
          },
        ),
        const SizedBox(height: 12),
        const EditorSectionLabel('LAYERS'),
        const SizedBox(height: 6),
        Row(
          children: [
            EditorLayerButton(
              icon: LucideIcons.arrowUpToLine,
              tooltip: 'Front',
              onTap: widget.ctrl.bringToFront,
            ),
            const SizedBox(width: 4),
            EditorLayerButton(
              icon: LucideIcons.arrowUp,
              tooltip: 'Up',
              onTap: widget.ctrl.bringForward,
            ),
            const SizedBox(width: 4),
            EditorLayerButton(
              icon: LucideIcons.arrowDown,
              tooltip: 'Down',
              onTap: widget.ctrl.sendBackward,
            ),
            const SizedBox(width: 4),
            EditorLayerButton(
              icon: LucideIcons.arrowDownToLine,
              tooltip: 'Back',
              onTap: widget.ctrl.sendToBack,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!isText) ..._buildNonTextControls(context, item),
        if (item.type == CanvasItemType.imageBox) _buildImageUploadButton(),
        if (item.type == CanvasItemType.icon)
          ..._buildIconPickerControls(context, item),
        if (widget.extraContentBuilder != null) ...[
          const SizedBox(height: 12),
          widget.extraContentBuilder!(item),
        ],
      ],
    );
  }

  // ── AI TOOLS — selected mode ────────────────────────────────────

  Widget _buildAiToolsForSelected(CanvasItem item) {
    final showCompose =
        widget.config.showAiCompose && widget.onCompose != null && _aiComposeEnabled;
    final showRefine =
        widget.config.showAiRefine && widget.onRefine != null && _aiRefineEnabled;
    final showProfile = (showCompose || showRefine) &&
        widget.config.showCareerProfileSelector &&
        widget.onPickCareerProfile != null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.lavenderBlush.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AiSectionHeader(label: 'AI TOOLS', icon: LucideIcons.sparkles),
          if (showProfile) ...[
            AiLabelTooltip(
              label: AiLabels.careerProfile,
              tip: AiTooltips.careerProfileSelector,
            ),
            const SizedBox(height: 4),
            _buildProfileSelector(),
            const SizedBox(height: 10),
          ],
          if (showCompose) ...[
            const AiLabelTooltip(
              label: 'Section Type',
              tip: 'Tells AI what kind of content to write for this section.',
            ),
            const SizedBox(height: 4),
            _buildSectionTypePill(item),
            const SizedBox(height: 10),
          ],
          if (showCompose) ...[
            AiLabelTooltip(
              label: AiLabels.aiCompose,
              tip: AiTooltips.aiCompose,
            ),
            const SizedBox(height: 6),
            _buildComposeButtons(item),
            const SizedBox(height: 12),
          ],
          if (showRefine) ...[
            AiLabelTooltip(label: AiLabels.aiRefine, tip: AiTooltips.aiRefine),
            const SizedBox(height: 6),
            _buildRefineButtons(item),
            if (_activeCustomMode == 'custom') ...[
              const SizedBox(height: 8),
              _buildCustomRefineBox(item),
            ],
          ],
        ],
      ),
    );
  }

  // ── AI TOOLS — all-sections mode ────────────────────────────────

  Widget _buildAiToolsForAll() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.lavenderBlush.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AiSectionHeader(label: 'AI TOOLS', icon: LucideIcons.sparkles),
          if (widget.onPickCareerProfile != null) ...[
            AiLabelTooltip(
              label: AiLabels.careerProfile,
              tip: AiTooltips.careerProfileSelector,
            ),
            const SizedBox(height: 4),
            _buildProfileSelector(),
            const SizedBox(height: 10),
          ],
          const AiLabelTooltip(
            label: 'AI Compose — All Sections',
            tip: 'Fills every fillable section in this CV at once.',
          ),
          const SizedBox(height: 6),
          _buildComposeAllButtons(),
        ],
      ),
    );
  }

  Widget _buildComposeAllButtons() {
    final busy = widget.isComposing;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 34,
          child: Tooltip(
            message: 'Fills every CV section using AI. Counts as 1 AI call.',
            child: ElevatedButton.icon(
              onPressed: busy ? null : () => widget.onComposeAll!(useAi: true),
              icon: busy
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(LucideIcons.sparkles, size: 12),
              label: Text(
                busy ? 'Composing all sections...' : AiLabels.composeWithAi,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.slateGrey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 30,
          child: Tooltip(
            message:
                'Copies Career Profile data into every section. No AI, no tokens.',
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => widget.onComposeAll!(useAi: false),
              icon: const Icon(
                LucideIcons.clipboardPaste,
                size: 11,
                color: AppColors.prussianBlue,
              ),
              label: Text(
                AiLabels.composeRaw,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.prussianBlue,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.almondSilk),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Career Profile pill ─────────────────────────────────────────

  Widget _buildProfileSelector() {
    final name = widget.selectedProfileName ?? 'Pick a profile';
    final hasProfile = widget.selectedProfileName != null;
    return GestureDetector(
      onTap: () async {
        await widget.onPickCareerProfile?.call();
        if (mounted) setState(() {});
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.almondSilk),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.userCircle,
                size: 13,
                color: AppColors.darkRaspberry,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: AppFonts.openSans,
                    color: hasProfile
                        ? AppColors.prussianBlue
                        : AppColors.slateGrey,
                    fontWeight: hasProfile
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: AppColors.slateGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section Type pill ───────────────────────────────────────────

  Widget _buildSectionTypePill(CanvasItem item) {
    return GestureDetector(
      onTap: () => _showSectionTypePicker(item),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.almondSilk),
          ),
          child: Row(
            children: [
              Icon(
                item.sectionType.isAutofillable
                    ? LucideIcons.fileText
                    : LucideIcons.fileQuestion,
                size: 13,
                color: AppColors.darkRaspberry,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.sectionType.label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: AppFonts.openSans,
                    color: AppColors.prussianBlue,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: AppColors.slateGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSectionTypePicker(CanvasItem item) async {
    final picked = await showModalBottomSheet<SectionType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.65,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    LucideIcons.fileText,
                    size: 14,
                    color: AppColors.darkRaspberry,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Section Type',
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    color: AppColors.prussianBlue,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  color: AppColors.slateGrey,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tells AI what kind of content to compose.',
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppFonts.openSans,
                color: AppColors.slateGrey,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: SectionType.values.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, i) {
                  final t = SectionType.values[i];
                  final isSelected = t == item.sectionType;
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, t),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.lavenderBlush
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.darkRaspberry
                              : AppColors.almondSilk,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            t.isAutofillable
                                ? LucideIcons.fileText
                                : LucideIcons.fileQuestion,
                            size: 14,
                            color: t.isAutofillable
                                ? AppColors.darkRaspberry
                                : AppColors.slateGrey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t.label,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontFamily: AppFonts.poppins,
                                fontWeight: FontWeight.w500,
                                color: AppColors.prussianBlue,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              LucideIcons.check,
                              size: 16,
                              color: AppColors.darkRaspberry,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null) {
      widget.ctrl.updateSectionType(picked);
    }
  }

  // ── Compose buttons ─────────────────────────────────────────────

  Widget _buildComposeButtons(CanvasItem item) {
    final canAutofill = item.sectionType.isAutofillable;
    final busy = widget.isComposing;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 34,
          child: Tooltip(
            message: AiTooltips.composeWithAi,
            child: ElevatedButton.icon(
              onPressed: (busy || !canAutofill)
                  ? null
                  : () => widget.onCompose!(item, useAi: true),
              icon: busy
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(LucideIcons.sparkles, size: 12),
              label: Text(
                busy ? 'Composing...' : AiLabels.composeWithAi,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.slateGrey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 30,
          child: Tooltip(
            message: AiTooltips.composeRaw,
            child: OutlinedButton.icon(
              onPressed: (busy || !canAutofill)
                  ? null
                  : () => widget.onCompose!(item, useAi: false),
              icon: const Icon(
                LucideIcons.clipboardPaste,
                size: 11,
                color: AppColors.prussianBlue,
              ),
              label: Text(
                AiLabels.composeRaw,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.prussianBlue,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.almondSilk),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        if (!canAutofill) ...[
          const SizedBox(height: 4),
          const Text(
            'Custom section — pick a section type above to enable AI Compose.',
            style: TextStyle(
              fontSize: 9.5,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  // ── Refine buttons ──────────────────────────────────────────────

  Widget _buildRefineButtons(CanvasItem item) {
    final busy = widget.isRefining;
    final presetModes = [
      (
        'professional',
        AiLabels.refineProfessional,
        AiTooltips.refineProfessional,
      ),
      ('concise', AiLabels.refineConcise, AiTooltips.refineConcise),
      ('detailed', AiLabels.refineDetailed, AiTooltips.refineDetailed),
      ('creative', AiLabels.refineCreative, AiTooltips.refineCreative),
    ];

    return Column(
      children: [
        for (int row = 0; row < 2; row++)
          Padding(
            padding: EdgeInsets.only(bottom: row == 1 ? 0 : 6),
            child: Row(
              children: [
                Expanded(
                  child: _buildRefineModeButton(
                    item: item,
                    mode: presetModes[row * 2].$1,
                    label: presetModes[row * 2].$2,
                    tip: presetModes[row * 2].$3,
                    busy: busy,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildRefineModeButton(
                    item: item,
                    mode: presetModes[row * 2 + 1].$1,
                    label: presetModes[row * 2 + 1].$2,
                    tip: presetModes[row * 2 + 1].$3,
                    busy: busy,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 30,
          child: Tooltip(
            message: AiTooltips.refineCustom,
            child: OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      _activeCustomMode = _activeCustomMode == 'custom'
                          ? null
                          : 'custom';
                    }),
              icon: Icon(
                _activeCustomMode == 'custom'
                    ? LucideIcons.chevronUp
                    : LucideIcons.messageSquare,
                size: 11,
                color: AppColors.darkRaspberry,
              ),
              label: Text(
                AiLabels.refineCustom,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.darkRaspberry,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.darkRaspberry),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRefineModeButton({
    required CanvasItem item,
    required String mode,
    required String label,
    required String tip,
    required bool busy,
  }) {
    return SizedBox(
      height: 30,
      child: Tooltip(
        message: tip,
        child: OutlinedButton(
          onPressed: busy ? null : () => widget.onRefine!(item, mode, null),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.almondSilk),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.prussianBlue,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildCustomRefineBox(CanvasItem item) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.darkRaspberry.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Tell AI how to rewrite this section. It will not add new sections — only rewrite what's here.",
            style: TextStyle(
              fontSize: 10,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _customInstructionCtrl,
            maxLines: 3,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: AppFonts.openSans,
              color: AppColors.prussianBlue,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. "Focus on metrics" or "Use a friendlier tone"',
              hintStyle: const TextStyle(
                color: AppColors.slateGrey,
                fontSize: 10,
              ),
              contentPadding: const EdgeInsets.all(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.darkRaspberry),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 30,
            child: ElevatedButton.icon(
              onPressed:
                  widget.isRefining ||
                      _customInstructionCtrl.text.trim().isEmpty
                  ? null
                  : () async {
                      final instruction = _customInstructionCtrl.text.trim();
                      await widget.onRefine!(item, 'custom', instruction);
                      if (mounted) {
                        setState(() {
                          _activeCustomMode = null;
                          _customInstructionCtrl.clear();
                        });
                      }
                    },
              icon: widget.isRefining
                  ? const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(LucideIcons.send, size: 11),
              label: Text(
                widget.isRefining ? 'Refining...' : 'Refine with Instructions',
                style: const TextStyle(fontSize: 10.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Misc shared pieces ──────────────────────────────────────────

  List<Widget> _buildNonTextControls(BuildContext context, CanvasItem item) {
    return [
      const EditorSectionLabel('FLIP'),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: EditorActionButton(
              label: 'Horizontal',
              icon: LucideIcons.flipHorizontal,
              onTap: widget.ctrl.flipHorizontal,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: EditorActionButton(
              label: 'Vertical',
              icon: LucideIcons.flipVertical,
              onTap: widget.ctrl.flipVertical,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (item.type != CanvasItemType.line && item.type != CanvasItemType.icon)
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
      EditorColorRow(
        label: item.type == CanvasItemType.line ? 'Line Color' : 'Border Color',
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
      if (item.type != CanvasItemType.imageBox &&
          item.type != CanvasItemType.icon)
        EditorSliderRow(
          label: item.type == CanvasItemType.line ? 'Thickness' : 'Border',
          value: item.borderWidth,
          min: 1,
          max: 12,
          onChanged: (v) => widget.ctrl.updateBorderWidth(v),
        ),
      const SizedBox(height: 8),
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
              onChanged: (v) => widget.ctrl.updateRotation(v * (math.pi / 180)),
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
    ];
  }

  Widget _buildImageUploadButton() {
    return SizedBox(
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
        label: const Text('Upload Image', style: TextStyle(fontSize: 12)),
      ),
    );
  }

  List<Widget> _buildIconPickerControls(BuildContext context, CanvasItem item) {
    return [
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
          label: const Text('Change Icon', style: TextStyle(fontSize: 12)),
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
    ];
  }

  Widget _buildTextClipboardRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              widget.ctrl.copySelectedText();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Text copied with formatting'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(
              LucideIcons.copy,
              size: 12,
              color: AppColors.prussianBlue,
            ),
            label: const Text(
              'Copy Text',
              style: TextStyle(color: AppColors.prussianBlue, fontSize: 10),
            ),
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
                ? () {
                    widget.ctrl.pasteFormattedText();
                    setState(() {});
                  }
                : null,
            icon: Icon(
              LucideIcons.clipboardPaste,
              size: 12,
              color: widget.ctrl.hasClipboardDelta
                  ? AppColors.prussianBlue
                  : AppColors.slateGrey,
            ),
            label: Text(
              'Paste Text',
              style: TextStyle(
                color: widget.ctrl.hasClipboardDelta
                    ? AppColors.prussianBlue
                    : AppColors.slateGrey,
                fontSize: 10,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: widget.ctrl.hasClipboardDelta
                    ? AppColors.almondSilk
                    : AppColors.petalFrost,
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOutlinedButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(vertical: 6),
        ),
      ),
    );
  }

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
          _buildOutlinedButton(
            label: 'Delete All',
            icon: LucideIcons.trash2,
            color: AppColors.error,
            onTap: () {
              widget.ctrl.saveSnapshot();
              widget.ctrl.deleteSelected();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPageSettings(BuildContext context) {
    final showAllSectionsBlock = widget.config.showAiCompose &&
        widget.onComposeAll != null &&
        _aiComposeEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAllSectionsBlock) ...[
          _buildAiToolsForAll(),
          const SizedBox(height: 14),
        ],
        if (widget.config.showPageSize) ...[
          const EditorSectionLabel('PAGE SETTINGS'),
          const SizedBox(height: 8),
          const Text(
            'Page Size',
            style: TextStyle(
              fontSize: 12,
              fontFamily: AppFonts.openSans,
              color: AppColors.prussianBlue,
            ),
          ),
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
                    child: Text(
                      'A4 (595 × 842)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'letter',
                    child: Text(
                      'Letter (612 × 792)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'legal',
                    child: Text(
                      'Legal (612 × 1008)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                onChanged: (v) {},
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.config.showBackground) ...[
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
        ],
        if (widget.onSpellcheck != null && _aiProofreadEnabled) ...[
          const AiSectionHeader(
            label: 'AI PROOFREAD',
            icon: LucideIcons.spellCheck,
          ),
          const SizedBox(height: 4),
          AiLabelTooltip(
            label: AiLabels.aiProofread,
            tip: AiTooltips.aiProofread,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 38,
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
                widget.isSpellchecking ? 'Checking...' : AiLabels.checkSpelling,
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
