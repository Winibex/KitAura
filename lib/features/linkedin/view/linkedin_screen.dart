// lib/features/linkedin/view/linkedin_screen.dart
//
// FULL REPLACEMENT — now reads AI profiles from the cached aiProfilesProvider
// instead of its own getAiProfiles() fetch. CVs still load locally (CV list
// is screen-specific and not shared). Profile dropdown + auto-select default
// are derived from the provider in build().
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/providers/ai_profiles_provider.dart';
import '../../../shared/services/firebase_service.dart';
import '../../../shared/widgets/responsive_scaffold.dart';
import '../../cover_letter/editor/controller/cl_editor_controller.dart';
import '../controller/linkedin_controller.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LinkedInScreen extends ConsumerStatefulWidget {
  const LinkedInScreen({super.key});
  @override
  ConsumerState<LinkedInScreen> createState() => _LinkedInScreenState();
}

class _LinkedInScreenState extends ConsumerState<LinkedInScreen> {
  final _promptCtrl = TextEditingController();
  List<CvDropdownItem> _cvList = [];
  bool _loadingCvs = true;
  String? _selectedProfileId;

  @override
  void initState() {
    super.initState();
    _loadCvs();
    Future.microtask(() {
      ref.read(linkedInControllerProvider.notifier).checkAiProfile();
      ref.read(linkedInControllerProvider.notifier).loadSaved();
    });
  }

  Future<void> _loadCvs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseService.getUserCVs(uid);
      final cvs = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return CvDropdownItem(
          id: doc.id,
          title: data['title'] ?? 'Untitled CV',
        );
      }).toList();
      if (mounted) {
        setState(() {
          _cvList = cvs;
          _loadingCvs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCvs = false);
    }
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(linkedInControllerProvider);

    // Profiles come from the shared cache (loaded once across the app).
    final profilesAsync = ref.watch(aiProfilesProvider);
    final profileList = profilesAsync.maybeWhen(
      data: (list) => list
          .map((p) => _ProfileDropdownItem(
        id: p.id ?? '',
        name: p.name,
        isDefault: p.isDefault,
        jobTitle: p.jobTitle ?? '',
      ))
          .toList(),
      orElse: () => <_ProfileDropdownItem>[],
    );
    final loadingProfiles = profilesAsync.isLoading;

    // Auto-select the default profile once profiles arrive.
    if (_selectedProfileId == null && profileList.isNotEmpty) {
      final def = profileList.where((p) => p.isDefault).firstOrNull;
      final chosen = def?.id ?? profileList.first.id;
      _selectedProfileId = chosen;
      // Inform the controller (after this frame to avoid setState-in-build).
      final name = profileList.firstWhere((p) => p.id == chosen).name;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(linkedInControllerProvider.notifier).selectProfile(chosen, name);
      });
    }

    return ResponsiveScaffold(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 28),
                if (!state.hasResults) ...[
                  _buildInputCard(state, profileList, loadingProfiles),
                ] else ...[
                  _buildResultsHeader(state),
                  const SizedBox(height: 16),
                  _buildResults(state),
                ],
                const SizedBox(height: 32),
                if (state.savedItems.isNotEmpty && !state.hasResults)
                  _buildSavedList(state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return ResponsiveBuilder(
      mobile: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.darkRaspberry.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(LucideIcons.linkedin, size: 20, color: AppColors.darkRaspberry),
          ),
          const SizedBox(height: 12),
          Text('LinkedIn Content Studio',
              style: TextStyle(
                  fontSize: AppSizes.headingLg(context),
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                  color: AppColors.prussianBlue)),
          const SizedBox(height: 4),
          Text('Generate optimized LinkedIn content from your CV & AI Profile',
              style: TextStyle(
                  fontSize: AppSizes.caption(context),
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey)),
        ],
      ),
      desktop: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.darkRaspberry.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(LucideIcons.linkedin, size: 24, color: AppColors.darkRaspberry),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LinkedIn Content Studio',
                    style: TextStyle(
                        fontSize: 24,
                        fontFamily: AppFonts.poppins,
                        fontWeight: FontWeight.bold,
                        color: AppColors.prussianBlue)),
                Text('Generate optimized LinkedIn content from your CV & AI Profile',
                    style: TextStyle(
                        fontSize: 13,
                        fontFamily: AppFonts.openSans,
                        color: AppColors.slateGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── INPUT CARD ─────────────────────────────────────────────────────
  Widget _buildInputCard(
      LinkedInState state,
      List<_ProfileDropdownItem> profileList,
      bool loadingProfiles,
      )
  {
    final ctrl = ref.read(linkedInControllerProvider.notifier);
    return Container(
      padding: EdgeInsets.all(AppSizes.pagePadding(context)),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE8E3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data Sources',
            style: TextStyle(
              fontSize: AppSizes.headingSm(context),
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w700,
              color: AppColors.prussianBlue,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose what AI should use to generate your LinkedIn content',
            style: TextStyle(
              fontSize: 12,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
            ),
          ),
          const SizedBox(height: 14),
          ResponsiveBuilder(
            mobile: Column(
              children: [
                _buildDropdownBlock(
                  icon: LucideIcons.sparkles,
                  label: 'AI Profile',
                  sublabel: 'Your career data & preferences',
                  child: loadingProfiles
                      ? _dropdownLoading()
                      : profileList.isEmpty
                      ? _dropdownEmpty('No profiles — create one in Settings')
                      : _buildProfileDropdown(profileList),
                ),
                const SizedBox(height: 14),
                _buildDropdownBlock(
                  icon: LucideIcons.fileText,
                  label: 'CV (Optional)',
                  sublabel: 'For richer, more detailed content',
                  child: _loadingCvs
                      ? _dropdownLoading()
                      : _cvList.isEmpty
                      ? _dropdownEmpty('No CVs yet')
                      : _buildCvDropdown(state, ctrl),
                ),
              ],
            ),
            desktop: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _buildDropdownBlock(
                      icon: LucideIcons.sparkles,
                      label: 'AI Profile',
                      sublabel: 'Your career data & preferences',
                      child: loadingProfiles
                          ? _dropdownLoading()
                          : profileList.isEmpty
                          ? _dropdownEmpty('No profiles — create one in Settings')
                          : _buildProfileDropdown(profileList),
                    )),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildDropdownBlock(
                      icon: LucideIcons.fileText,
                      label: 'CV (Optional)',
                      sublabel: 'For richer, more detailed content',
                      child: _loadingCvs
                          ? _dropdownLoading()
                          : _cvList.isEmpty
                          ? _dropdownEmpty('No CVs yet')
                          : _buildCvDropdown(state, ctrl),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFF0EBE6)),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Sections to Generate',
                style: TextStyle(
                  fontSize: AppSizes.headingSm(context),
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w700,
                  color: AppColors.prussianBlue,
                ),
              ),
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: ctrl.toggleAll,
                  child: Row(
                    children: [
                      Icon(
                        state.allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                        color: state.allSelected ? AppColors.darkRaspberry : AppColors.slateGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        state.allSelected ? 'Deselect All' : 'Select All',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: AppFonts.poppins,
                          fontWeight: FontWeight.w500,
                          color: AppColors.darkRaspberry,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kLinkedInSections.map((section) {
              final selected = state.selectedSections.contains(section.key);
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => ctrl.toggleSection(section.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.darkRaspberry.withValues(alpha: 0.08)
                          : AppColors.lavenderBlush,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? AppColors.darkRaspberry : AppColors.almondSilk,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? Icons.check_circle : Icons.circle_outlined,
                          size: 16,
                          color: selected ? AppColors.darkRaspberry : AppColors.slateGrey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          section.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: AppFonts.poppins,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected ? AppColors.darkRaspberry : AppColors.prussianBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFF0EBE6)),
          const SizedBox(height: 20),
          Text(
            'Custom Instructions',
            style: TextStyle(
              fontSize: AppSizes.headingSm(context),
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w700,
              color: AppColors.prussianBlue,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Optional — guide the AI on tone, focus areas, or keywords',
            style: TextStyle(
              fontSize: 12,
              fontFamily: AppFonts.openSans,
              color: AppColors.slateGrey,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _promptCtrl,
            maxLines: 3,
            onChanged: ctrl.setPrompt,
            style: const TextStyle(fontSize: 13, fontFamily: AppFonts.openSans),
            decoration: InputDecoration(
              hintText:
              'e.g. Focus on leadership. Target fintech companies. Highlight AI/ML skills.',
              hintStyle: TextStyle(
                color: AppColors.slateGrey.withValues(alpha: 0.5),
                fontSize: 12,
              ),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.darkRaspberry),
              ),
            ),
          ),
          if (!state.hasAiProfile && _cvList.isEmpty && !_loadingCvs && !loadingProfiles) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.petalFrost,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.almondSilk),
              ),
              child: const Row(
                children: [
                  Icon(LucideIcons.info, size: 16, color: AppColors.darkRaspberry),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Create a CV or set up an AI Profile in Settings to get started.',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: AppFonts.openSans,
                        color: AppColors.prussianBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
              ),
              child: Text(
                state.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (state.isGenerating || !state.canGenerate)
                  ? null
                  : () => ref.read(linkedInControllerProvider.notifier).generate(),
              icon: state.isGenerating
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
              )
                  : const Icon(LucideIcons.sparkles, size: 18),
              label: Text(
                state.isGenerating
                    ? 'Generating ${state.selectedSections.length} sections...'
                    : 'Generate LinkedIn Content (${state.selectedSections.length} sections)',
                style: const TextStyle(fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkRaspberry,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.slateGrey,
                disabledForegroundColor: AppColors.white.withValues(alpha: 0.7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dropdown building blocks ───────────────────────────────────────
  Widget _buildDropdownBlock({
    required IconData icon,
    required String label,
    required String sublabel,
    required Widget child,
  })
  {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.darkRaspberry),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.w600,
                color: AppColors.prussianBlue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          sublabel,
          style: const TextStyle(
            fontSize: 11,
            fontFamily: AppFonts.openSans,
            color: AppColors.slateGrey,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildProfileDropdown(List<_ProfileDropdownItem> profileList) {
    return Container(
      width: double.infinity,
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.almondSilk),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: (_selectedProfileId != null &&
              profileList.any((p) => p.id == _selectedProfileId))
              ? _selectedProfileId
              : null,
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          borderRadius: BorderRadius.circular(10),
          icon: const Icon(LucideIcons.chevronDown, size: 14, color: AppColors.slateGrey),
          items: profileList
              .map(
                (p) => DropdownMenuItem<String?>(
              value: p.id,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    size: 13,
                    color: p.isDefault ? AppColors.success : AppColors.slateGrey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.isDefault ? '${p.name} (default)' : p.name,
                      style: const TextStyle(fontSize: 12, fontFamily: AppFonts.openSans),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
              .toList(),
          onChanged: (id) {
            setState(() => _selectedProfileId = id);
            if (id != null) {
              final p = profileList.firstWhere((p) => p.id == id);
              ref.read(linkedInControllerProvider.notifier).selectProfile(id, p.name);
            }
          },
        ),
      ),
    );
  }

  Widget _buildCvDropdown(LinkedInState state, LinkedInController ctrl) {
    return Container(
      width: double.infinity,
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.almondSilk),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: state.selectedCvId,
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          borderRadius: BorderRadius.circular(10),
          hint: const Text('None selected',
              style: TextStyle(fontSize: 12, color: AppColors.slateGrey)),
          icon: const Icon(LucideIcons.chevronDown, size: 14, color: AppColors.slateGrey),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('None — use AI Profile only',
                  style: TextStyle(fontSize: 12, color: AppColors.slateGrey)),
            ),
            ..._cvList.map(
                  (cv) => DropdownMenuItem<String?>(
                value: cv.id,
                child: Row(
                  children: [
                    const Icon(LucideIcons.fileText, size: 13, color: AppColors.darkRaspberry),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(cv.title,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ],
          onChanged: (id) {
            if (id == null) {
              ctrl.clearCv();
            } else {
              final title = _cvList.firstWhere((c) => c.id == id).title;
              ctrl.selectCv(id, title);
            }
          },
        ),
      ),
    );
  }

  Widget _dropdownLoading() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.almondSilk),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.darkRaspberry),
        ),
      ),
    );
  }

  Widget _dropdownEmpty(String message) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.lavenderBlush,
        border: Border.all(color: AppColors.almondSilk),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(message, style: const TextStyle(fontSize: 11, color: AppColors.slateGrey)),
      ),
    );
  }

  // ── RESULTS HEADER ─────────────────────────────────────────────────
  Widget _buildResultsHeader(LinkedInState state) {
    final ctrl = ref.read(linkedInControllerProvider.notifier);
    return ResponsiveBuilder(
      mobile: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Generated Content',
              style: TextStyle(
                  fontSize: AppSizes.headingMd(context),
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                  color: AppColors.prussianBlue)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _headerAction(LucideIcons.plus, 'New', ctrl.clearResults)),
              const SizedBox(width: 8),
              Expanded(
                  child: _headerAction(LucideIcons.copy, 'Copy All', () async {
                    await ctrl.copyAll();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('All content copied'),
                            backgroundColor: AppColors.success,
                            duration: Duration(seconds: 2)),
                      );
                    }
                  }, filled: true)),
            ],
          ),
        ],
      ),
      desktop: Row(
        children: [
          const Text('Generated Content',
              style: TextStyle(
                  fontSize: 18,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                  color: AppColors.prussianBlue)),
          const Spacer(),
          _headerAction(LucideIcons.plus, 'New', ctrl.clearResults),
          const SizedBox(width: 8),
          _headerAction(LucideIcons.copy, 'Copy All', () async {
            await ctrl.copyAll();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('All content copied'),
                    backgroundColor: AppColors.success,
                    duration: Duration(seconds: 2)),
              );
            }
          }, filled: true),
        ],
      ),
    );
  }

  Widget _headerAction(IconData icon, String label, VoidCallback onTap, {bool filled = false}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: filled ? AppColors.darkRaspberry : Colors.transparent,
            border: filled ? null : Border.all(color: AppColors.almondSilk),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: filled ? AppColors.white : AppColors.prussianBlue),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w500,
                  color: filled ? AppColors.white : AppColors.prussianBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── RESULTS CARDS ──────────────────────────────────────────────────
  Widget _buildResults(LinkedInState state) {
    final content = state.generatedContent!;
    final ctrl = ref.read(linkedInControllerProvider.notifier);
    return Column(
      children: kLinkedInSections.map((section) {
        final data = content[section.key];
        if (data == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEDE8E3)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: section.key == 'headline' || section.key == 'about',
              tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.darkRaspberry.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(section.icon, size: 16, color: AppColors.darkRaspberry),
              ),
              title: Text(
                section.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                  color: AppColors.prussianBlue,
                ),
              ),
              trailing: Responsive.isMobile(context)
                  ? const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.slateGrey)
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.regeneratingSection == section.key)
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.lavenderBlush,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.darkRaspberry)),
                    )
                  else
                    _iconBtn(
                        LucideIcons.refreshCw,
                        state.isGenerating
                            ? null
                            : () => ctrl.regenerateSection(section.key),
                        AppColors.lavenderBlush,
                        AppColors.darkRaspberry),
                  const SizedBox(width: 6),
                  _iconBtn(LucideIcons.copy, () async {
                    await ctrl.copySection(section.key);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('${section.label} copied'),
                            backgroundColor: AppColors.success,
                            duration: const Duration(seconds: 1)),
                      );
                    }
                  }, AppColors.petalFrost, AppColors.darkRaspberry),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.slateGrey),
                ],
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.lavenderBlush,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    ctrl.formatSectionText(section.key, data),
                    style: TextStyle(
                        fontSize: AppSizes.body(context),
                        fontFamily: AppFonts.openSans,
                        color: AppColors.prussianBlue,
                        height: 1.6),
                  ),
                ),
                if (Responsive.isMobile(context)) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: state.isGenerating
                              ? null
                              : () => ctrl.regenerateSection(section.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.lavenderBlush,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                state.regeneratingSection == section.key
                                    ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppColors.darkRaspberry))
                                    : const Icon(LucideIcons.refreshCw,
                                    size: 14, color: AppColors.darkRaspberry),
                                const SizedBox(width: 6),
                                Text('Regenerate',
                                    style: TextStyle(
                                        fontSize: AppSizes.caption(context),
                                        fontFamily: AppFonts.poppins,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.darkRaspberry)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            await ctrl.copySection(section.key);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('${section.label} copied'),
                                    backgroundColor: AppColors.success,
                                    duration: const Duration(seconds: 1)),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.darkRaspberry.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.copy, size: 14, color: AppColors.darkRaspberry),
                                const SizedBox(width: 6),
                                Text('Copy',
                                    style: TextStyle(
                                        fontSize: AppSizes.caption(context),
                                        fontFamily: AppFonts.poppins,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.darkRaspberry)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, Color bg, Color fg) {
    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 13, color: onTap != null ? fg : AppColors.slateGrey),
        ),
      ),
    );
  }

  // ── SAVED LIST ─────────────────────────────────────────────────────
  Widget _buildSavedList(LinkedInState state) {
    final ctrl = ref.read(linkedInControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Previous Generations',
          style: TextStyle(
            fontSize: 16,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w600,
            color: AppColors.prussianBlue,
          ),
        ),
        const SizedBox(height: 12),
        ...state.savedItems.map(
              (item) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEDE8E3)),
            ),
            child: ListTile(
              onTap: () => ctrl.loadSavedGeneration(item.id),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.darkRaspberry.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.linkedin, size: 16, color: AppColors.darkRaspberry),
              ),
              title: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w500,
                  color: AppColors.prussianBlue,
                ),
              ),
              subtitle: Text(
                '${item.linkedCvTitle ?? "AI Profile only"} · ${item.timeAgo}',
                style: const TextStyle(fontSize: 11, color: AppColors.slateGrey),
              ),
              trailing: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => ctrl.deleteSaved(item.id),
                  child: const Icon(LucideIcons.trash2, size: 15, color: AppColors.error),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helper model ─────────────────────────────────────────────────────
class _ProfileDropdownItem {
  final String id;
  final String name;
  final bool isDefault;
  final String jobTitle;
  const _ProfileDropdownItem({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.jobTitle,
  });
}