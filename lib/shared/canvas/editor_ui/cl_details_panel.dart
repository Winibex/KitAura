// lib/shared/canvas/editor_ui/cl_details_panel.dart
//
// Cover Letter-specific right panel section. Shows:
//   - Job details form
//   - Career Profile dropdown (NEW — Phase D)
//   - CV link dropdown
//   - AI Generate Cover Letter button
//   - AI Proofread button

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/constants/app_ai_labels.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../features/cover_letter/editor/controller/cl_editor_controller.dart';
import 'editor_widgets.dart';

/// Callback for the Career Profile selector. Parent shows the picker modal
/// and returns the chosen profile name (or null if cancelled).
typedef PickCareerProfileCallback = Future<String?> Function();

class ClDetailsPanel extends StatefulWidget {
  final ClEditorController editor;
  final VoidCallback? onSpellcheck;
  final bool isSpellchecking;
  final Future<void> Function()? onGenerateAll;
  final bool isGenerating;
  final PickCareerProfileCallback? onPickCareerProfile;

  const ClDetailsPanel({
    super.key,
    required this.editor,
    this.onSpellcheck,
    this.isSpellchecking = false,
    this.onGenerateAll,
    this.isGenerating = false,
    this.onPickCareerProfile,
  });

  @override
  State<ClDetailsPanel> createState() => _ClDetailsPanelState();
}

class _ClDetailsPanelState extends State<ClDetailsPanel> {
  final _companyCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _managerNameCtrl = TextEditingController();
  final _managerTitleCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  List<CvDropdownItem> _cvList = [];
  bool _loadingCvs = true;

  @override
  void initState() {
    super.initState();
    _syncFromState();
    _loadCvs();
    widget.editor.addListener(_onEditorUpdate);
  }

  void _onEditorUpdate() {
    if (!mounted) return;
    if (_companyCtrl.text.isEmpty &&
        (widget.editor.state.targetCompany ?? '').isNotEmpty) {
      _syncFromState();
      setState(() {});
    }
    // Also rebuild when profile selection changes so the pill updates.
    setState(() {});
  }

  void _syncFromState() {
    final s = widget.editor.state;
    _companyCtrl.text = s.targetCompany ?? '';
    _roleCtrl.text = s.targetRole ?? '';
    _managerNameCtrl.text = s.hiringManagerName ?? '';
    _managerTitleCtrl.text = s.hiringManagerTitle ?? '';
    _addressCtrl.text = s.companyAddress ?? '';
    _cityCtrl.text = s.companyCityStateZip ?? '';
    _descriptionCtrl.text = s.jobDescription ?? '';
  }

  Future<void> _loadCvs() async {
    final cvs = await widget.editor.getUserCvs();
    if (mounted) {
      setState(() {
        _cvList = cvs;
        _loadingCvs = false;
      });
    }
  }

  void _saveDetails() {
    widget.editor.updateJobDetails(
      targetCompany: _companyCtrl.text.trim(),
      targetRole: _roleCtrl.text.trim(),
      hiringManagerName: _managerNameCtrl.text.trim(),
      hiringManagerTitle: _managerTitleCtrl.text.trim(),
      companyAddress: _addressCtrl.text.trim(),
      companyCityStateZip: _cityCtrl.text.trim(),
      jobDescription: _descriptionCtrl.text.trim(),
    );
  }

  @override
  void dispose() {
    widget.editor.removeListener(_onEditorUpdate);
    _companyCtrl.dispose();
    _roleCtrl.dispose();
    _managerNameCtrl.dispose();
    _managerTitleCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.editor.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Job Details ────────────────────────────────────────────
        const EditorSectionLabel('JOB DETAILS'),
        const SizedBox(height: 8),
        _field('Company Name', _companyCtrl, LucideIcons.building2),
        _field('Job Role / Title', _roleCtrl, LucideIcons.briefcase),
        _field('Hiring Manager Name', _managerNameCtrl, LucideIcons.user),
        _field(
          'Manager Title',
          _managerTitleCtrl,
          LucideIcons.badge,
          hint: 'e.g. Director of Engineering',
        ),
        _field('Company Address', _addressCtrl, LucideIcons.mapPin),
        _field(
          'City, State ZIP',
          _cityCtrl,
          LucideIcons.map,
          hint: 'e.g. San Francisco, CA 94105',
        ),
        const SizedBox(height: 8),

        const EditorSectionLabel('JOB DESCRIPTION'),
        const SizedBox(height: 6),
        TextField(
          controller: _descriptionCtrl,
          maxLines: 4,
          style: const TextStyle(fontSize: 11, fontFamily: AppFonts.openSans),
          decoration: InputDecoration(
            hintText: 'Paste the job description here...',
            hintStyle: TextStyle(
              color: AppColors.slateGrey.withValues(alpha: 0.6),
              fontSize: 11,
            ),
            contentPadding: const EdgeInsets.all(10),
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
        const SizedBox(height: 16),

        // ── Career Profile ─────────────────────────────────────────
        if (widget.onPickCareerProfile != null) ...[
          AiLabelTooltip(
            label: AiLabels.careerProfile,
            tip: AiTooltips.careerProfileSelector,
          ),
          const SizedBox(height: 4),
          Text(
            'AI uses this profile to personalize the letter',
            style: TextStyle(
              color: AppColors.slateGrey.withValues(alpha: 0.7),
              fontSize: 10,
              fontFamily: AppFonts.openSans,
            ),
          ),
          const SizedBox(height: 6),
          _buildProfileSelector(),
          const SizedBox(height: 16),
        ],

        // ── Link a CV ──────────────────────────────────────────────
        const EditorSectionLabel('LINK A CV'),
        const SizedBox(height: 4),
        Text(
          'AI will use your CV content for additional context',
          style: TextStyle(
            color: AppColors.slateGrey.withValues(alpha: 0.7),
            fontSize: 10,
            fontFamily: AppFonts.openSans,
          ),
        ),
        const SizedBox(height: 6),
        _loadingCvs
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.darkRaspberry,
                    ),
                  ),
                ),
              )
            : Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.almondSilk),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: s.linkedCvId,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    borderRadius: BorderRadius.circular(8),
                    hint: const Text(
                      'Select a CV (optional)',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.slateGrey,
                        fontFamily: AppFonts.openSans,
                      ),
                    ),
                    icon: const Icon(
                      LucideIcons.chevronDown,
                      size: 14,
                      color: AppColors.slateGrey,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          "None — don't link a CV",
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.slateGrey,
                            fontFamily: AppFonts.openSans,
                          ),
                        ),
                      ),
                      ..._cvList.map(
                        (cv) => DropdownMenuItem<String?>(
                          value: cv.id,
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.fileText,
                                size: 12,
                                color: AppColors.darkRaspberry,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  cv.title,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: AppFonts.openSans,
                                    color: AppColors.prussianBlue,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    onChanged: (cvId) {
                      if (cvId == null) {
                        widget.editor.clearLinkedCv();
                      } else {
                        widget.editor.updateJobDetails(linkedCvId: cvId);
                      }
                      setState(() {});
                    },
                  ),
                ),
              ),
        if (s.linkedCvId != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                LucideIcons.link,
                size: 10,
                color: AppColors.success.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Linked: ${_cvList.where((c) => c.id == s.linkedCvId).map((c) => c.title).firstOrNull ?? 'CV'}',
                  style: TextStyle(
                    color: AppColors.success.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontFamily: AppFonts.openSans,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),

        // ── AI Generate Cover Letter ───────────────────────────────
        const AiSectionHeader(label: 'AI TOOLS', icon: LucideIcons.sparkles),
        const SizedBox(height: 4),
        AiLabelTooltip(
          label: AiLabels.aiComposeLetter,
          tip: AiTooltips.aiComposeLetter,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton.icon(
            onPressed: (widget.isGenerating || !s.hasJobDetails)
                ? null
                : () async {
                    _saveDetails();
                    await widget.editor.saveNow();
                    widget.onGenerateAll?.call();
                  },
            icon: widget.isGenerating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : const Icon(LucideIcons.sparkles, size: 16),
            label: Text(
              widget.isGenerating
                  ? 'Generating cover letter...'
                  : AiLabels.aiComposeLetter,
              style: const TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: (widget.isGenerating || !s.hasJobDetails)
                  ? AppColors.slateGrey
                  : AppColors.darkRaspberry,
              foregroundColor: AppColors.white,
              disabledBackgroundColor: AppColors.slateGrey,
              disabledForegroundColor: AppColors.white.withValues(alpha: 0.7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        if (!s.hasJobDetails) ...[
          const SizedBox(height: 4),
          const Text(
            'Fill in at least company name or job role to generate',
            style: TextStyle(
              fontSize: 10,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
            ),
          ),
        ],
        const SizedBox(height: 8),

        // ── Spellcheck (AI Proofread) ──────────────────────────────
        if (widget.onSpellcheck != null) ...[
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
                  : const Icon(LucideIcons.spellCheck, size: 14),
              label: Text(
                widget.isSpellchecking ? 'Checking...' : AiLabels.checkSpelling,
                style: const TextStyle(fontSize: 11),
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

  // ── Career Profile pill (matches CV editor's selector) ──────────

  Widget _buildProfileSelector() {
    final name = widget.editor.state.selectedProfileName ?? 'Pick a profile';
    final hasProfile = widget.editor.state.selectedProfileName != null;
    return GestureDetector(
      onTap: () async {
        await widget.onPickCareerProfile?.call();
        if (mounted) setState(() {});
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.almondSilk),
          ),
          child: Row(
            children: [
              const Icon(
                LucideIcons.userCircle,
                size: 14,
                color: AppColors.darkRaspberry,
              ),
              const SizedBox(width: 8),
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

  Widget _field(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 11, fontFamily: AppFonts.openSans),
          decoration: InputDecoration(
            hintText: hint ?? label,
            hintStyle: TextStyle(
              color: AppColors.slateGrey.withValues(alpha: 0.6),
              fontSize: 11,
            ),
            prefixIcon: Icon(icon, size: 14, color: AppColors.slateGrey),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
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
      ),
    );
  }
}
