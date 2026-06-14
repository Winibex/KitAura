// lib/features/proposal/editor/view/prop_details_panel.dart
//
// Right panel for proposal editor. Shows:
//   - Client Profile selector + New/Edit client wizard
//   - Linked CV dropdown
//   - AI Generate Proposal button
//   - AI Spellcheck button

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../shared/canvas/editor_ui/editor_widgets.dart';
import '../../../../shared/models/client_profile_model.dart';
import '../../../../shared/services/firebase_service.dart';
import '../../../../shared/widgets/client_wizard_modal.dart';
import '../controller/prop_editor_controller.dart';

class PropDetailsPanel extends StatefulWidget {
  final PropEditorController editor;
  final VoidCallback? onSpellcheck;
  final bool isSpellchecking;
  final Future<void> Function()? onGenerateAll;
  final bool isGenerating;

  const PropDetailsPanel({
    super.key,
    required this.editor,
    this.onSpellcheck,
    this.isSpellchecking = false,
    this.onGenerateAll,
    this.isGenerating = false,
  });

  @override
  State<PropDetailsPanel> createState() => _PropDetailsPanelState();
}

class _PropDetailsPanelState extends State<PropDetailsPanel> {
  List<ClientProfileModel> _clients = [];
  List<CvDropdownItem> _cvList = [];
  bool _loadingClients = true;
  bool _loadingCvs = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _loadCvs();
    widget.editor.addListener(_onEditorUpdate);
  }

  void _onEditorUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadClients() async {
    final clients = await widget.editor.getClientProfiles();
    if (mounted) setState(() { _clients = clients; _loadingClients = false; });
  }

  Future<void> _loadCvs() async {
    final cvs = await widget.editor.getUserCvs();
    if (mounted) setState(() { _cvList = cvs; _loadingCvs = false; });
  }

  Future<void> _openNewClientWizard() async {
    final client = await ClientWizardModal.show(context);
    if (client == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final id = await FirebaseService.saveClientProfile(uid, client.toJson());
    final saved = client.copyWith(id: id);

    widget.editor.linkClient(saved);
    await _loadClients(); // Refresh dropdown
  }

  Future<void> _openEditClientWizard() async {
    final clientId = widget.editor.state.linkedClientId;
    if (clientId == null) return;

    // Find the current client in the list
    final current = _clients.where((c) => c.id == clientId).firstOrNull;
    if (current == null) return;

    final updated = await ClientWizardModal.show(context, existing: current);
    if (updated == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseService.saveClientProfile(uid, updated.toJson(),
        clientId: clientId);
    widget.editor.linkClient(updated.copyWith(id: clientId));
    await _loadClients();
  }

  @override
  void dispose() {
    widget.editor.removeListener(_onEditorUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.editor.state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Client Profile ─────────────────────────────────────────
        const EditorSectionLabel('CLIENT'),
        const SizedBox(height: 4),
        Text(
          'Select a saved client or create a new one',
          style: TextStyle(
            color: AppColors.slateGrey.withValues(alpha: 0.7),
            fontSize: 10,
            fontFamily: AppFonts.openSans,
          ),
        ),
        const SizedBox(height: 8),

        // Client dropdown
        _loadingClients
            ? _loadingIndicator()
            : Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.almondSilk),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _clients.any((c) => c.id == s.linkedClientId)
                  ? s.linkedClientId
                  : null,
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              borderRadius: BorderRadius.circular(8),
              hint: const Text(
                'Select a client...',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.slateGrey,
                  fontFamily: AppFonts.openSans,
                ),
              ),
              icon: const Icon(LucideIcons.chevronDown,
                  size: 14, color: AppColors.slateGrey),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'No client selected',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.slateGrey,
                      fontFamily: AppFonts.openSans,
                    ),
                  ),
                ),
                ..._clients.map((c) => DropdownMenuItem<String?>(
                  value: c.id,
                  child: Row(
                    children: [
                      const Icon(LucideIcons.building2,
                          size: 12, color: AppColors.darkRaspberry),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.displayName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: AppFonts.openSans,
                                color: AppColors.prussianBlue,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (c.projectTitle.isNotEmpty)
                              Text(
                                c.projectTitle,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontFamily: AppFonts.openSans,
                                  color: AppColors.slateGrey
                                      .withValues(alpha: 0.7),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
              ],
              onChanged: (clientId) {
                if (clientId == null) {
                  widget.editor.unlinkClient();
                } else {
                  final client =
                  _clients.firstWhere((c) => c.id == clientId);
                  widget.editor.linkClient(client);
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 8),

        // New + Edit buttons
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: LucideIcons.userPlus,
                label: 'New Client',
                onTap: _openNewClientWizard,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                icon: LucideIcons.pencil,
                label: 'Edit Client',
                onTap: s.hasClientLinked ? _openEditClientWizard : null,
              ),
            ),
          ],
        ),

        // Linked client info
        if (s.hasClientLinked) ...[
          const SizedBox(height: 8),
          _linkedInfo(
            icon: LucideIcons.building2,
            text: s.clientName ?? 'Client',
            subtitle: s.projectScope,
          ),
        ],

        const SizedBox(height: 20),

        // ── Linked CV ──────────────────────────────────────────────
        const EditorSectionLabel('LINK A CV (OPTIONAL)'),
        const SizedBox(height: 4),
        Text(
          'AI will reference your credentials',
          style: TextStyle(
            color: AppColors.slateGrey.withValues(alpha: 0.7),
            fontSize: 10,
            fontFamily: AppFonts.openSans,
          ),
        ),
        const SizedBox(height: 6),

        _loadingCvs
            ? _loadingIndicator()
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
              icon: const Icon(LucideIcons.chevronDown,
                  size: 14, color: AppColors.slateGrey),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.slateGrey,
                          fontFamily: AppFonts.openSans)),
                ),
                ..._cvList.map((cv) => DropdownMenuItem<String?>(
                  value: cv.id,
                  child: Row(
                    children: [
                      const Icon(LucideIcons.fileText,
                          size: 12,
                          color: AppColors.darkRaspberry),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(cv.title,
                            style: const TextStyle(
                                fontSize: 11,
                                fontFamily: AppFonts.openSans,
                                color: AppColors.prussianBlue),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                )),
              ],
              onChanged: (cvId) {
                if (cvId == null) {
                  widget.editor.unlinkCv();
                } else {
                  widget.editor.linkCv(cvId);
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── AI Tools ───────────────────────────────────────────────
        const EditorSectionLabel('AI TOOLS'),
        const SizedBox(height: 8),

        // AI Generate Proposal
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton.icon(
            onPressed: (widget.isGenerating || !s.hasClientLinked)
                ? null
                : () async {
              await widget.editor.saveNow();
              widget.onGenerateAll?.call();
            },
            icon: widget.isGenerating
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.white),
            )
                : const Icon(LucideIcons.sparkles, size: 16),
            label: Text(
              widget.isGenerating
                  ? 'Generating proposal...'
                  : 'AI Generate Proposal',
              style: const TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: (widget.isGenerating || !s.hasClientLinked)
                  ? AppColors.slateGrey
                  : AppColors.darkRaspberry,
              foregroundColor: AppColors.white,
              disabledBackgroundColor: AppColors.slateGrey,
              disabledForegroundColor:
              AppColors.white.withValues(alpha: 0.7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),

        if (!s.hasClientLinked) ...[
          const SizedBox(height: 4),
          const Text(
            'Select or create a client to enable AI generation',
            style: TextStyle(
              fontSize: 10,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
            ),
          ),
        ],

        const SizedBox(height: 8),

        // AI Spellcheck
        if (widget.onSpellcheck != null)
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed:
              widget.isSpellchecking ? null : widget.onSpellcheck,
              icon: widget.isSpellchecking
                  ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.white),
              )
                  : const Icon(LucideIcons.spellCheck, size: 14),
              label: Text(
                widget.isSpellchecking ? 'Checking...' : 'AI Spellcheck',
                style: const TextStyle(fontSize: 11),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.prussianBlue,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.slateGrey,
                disabledForegroundColor:
                AppColors.white.withValues(alpha: 0.7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── HELPERS ────────────────────────────────────────────────────

  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor:
        enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? AppColors.petalFrost : const Color(0xFFF5F0EC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 13,
                  color: enabled
                      ? AppColors.darkRaspberry
                      : AppColors.almondSilk),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? AppColors.darkRaspberry
                        : AppColors.almondSilk,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkedInfo(
      {required IconData icon, required String text, String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.petalFrost.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.darkRaspberry),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: const TextStyle(
                        fontSize: 11,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.w600,
                        color: AppColors.prussianBlue),
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 9,
                          fontFamily: AppFonts.openSans,
                          color: AppColors.slateGrey),
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => widget.editor.unlinkClient(),
            child: const Icon(LucideIcons.x,
                size: 12, color: AppColors.slateGrey),
          ),
        ],
      ),
    );
  }

  Widget _loadingIndicator() {
    return const Center(
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
    );
  }
}