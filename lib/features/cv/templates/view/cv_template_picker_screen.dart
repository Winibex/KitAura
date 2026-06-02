import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kitaura/core/constants/app_routes.dart';
import 'package:kitaura/shared/widgets/app_top_bar.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_fonts.dart';
import '../../../../shared/services/firebase_service.dart';
import '../../../ai_setup/view/ai_setup_panel.dart';
import '../controller/cv_template_controller.dart';
import '../../../../shared/models/template_model.dart';
import 'cv_template_card_widget.dart';
import 'cv_template_preview_modal.dart';

class CVTemplatePickerScreen extends ConsumerStatefulWidget {
  const CVTemplatePickerScreen({super.key});

  @override
  ConsumerState<CVTemplatePickerScreen> createState() =>
      _CVTemplatePickerScreenState();
}

class _CVTemplatePickerScreenState extends ConsumerState<CVTemplatePickerScreen> {

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(templateControllerProvider);

    return Material(
      color: AppColors.lavenderBlush,
      child: Column(
        children: [
          AppTopBar(
            canBack: true,
            whereToGo: AppRoutes.cvDashboard,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildSearchAndFilter(state),
                  const SizedBox(height: 24),
                  _buildGrid(state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose a Template',
          style: TextStyle(
            color: AppColors.prussianBlue,
            fontSize: 26,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Start with a professionally designed layout or begin from scratch',
          style: TextStyle(
            color: AppColors.slateGrey,
            fontSize: 14,
            fontFamily: AppFonts.openSans,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilter(CVTemplateState state) {
    return Row(
      children: [
        SizedBox(
          width: 280,
          height: 42,
          child: TextField(
            onChanged: (v) =>
                ref.read(templateControllerProvider.notifier).setSearch(v),
            decoration: InputDecoration(
              hintText: 'Search cv templates...',
              prefixIcon: const Icon(LucideIcons.search,
                  size: 16, color: AppColors.slateGrey),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.almondSilk),
              ),
              filled: true,
              fillColor: AppColors.white,
            ),
          ),
        ),
        const Spacer(),
        ...CVTemplateController.categories.map((cat) {
          final isActive = state.activeFilter == cat;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: GestureDetector(
              onTap: () => ref
                  .read(templateControllerProvider.notifier)
                  .setFilter(cat),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color:
                  isActive ? AppColors.darkRaspberry : AppColors.white,
                  borderRadius: BorderRadius.circular(8),
                  border:
                  isActive ? null : Border.all(color: AppColors.almondSilk),
                ),
                child: Text(
                  cat,
                  style: TextStyle(
                    color: isActive
                        ? AppColors.white
                        : AppColors.prussianBlue,
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGrid(CVTemplateState state) {
    final templates = state.filteredTemplates;

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = 4;
        if (constraints.maxWidth < 500) columns = 1;
        if (constraints.maxWidth < 700) columns = 2;
        if (constraints.maxWidth < 1000) columns = 3;

        if (templates.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(
              child: Text(
                'No CV templates match your search',
                style: TextStyle(color: AppColors.slateGrey, fontSize: 14),
              ),
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final template = templates[index];
            return CVTemplateCardWidget(
              template: template,
              onTap: () => _showPreviewModal(template),
            );
          },
        );
      },
    );
  }

  // ─── TEMPLATE FLOW ────────────────────────────────────────────────────

  void _showPreviewModal(TemplateModel template) {
    showDialog(
      context: context,
      builder: (_) => CVTemplatePreviewModal(
        template: template,
        onUseTemplate: () {
          _handleTemplateSelected(template.id);  // ← routes through AI setup
        },
        onStartBlank: () {
          _handleTemplateSelected('blank');  // ← blank also gets AI setup option
        },
      ),
    );
  }

  void _handleTemplateSelected(String templateId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    bool hasSavedProfile = false;
    try {
      final doc = await FirebaseService.getAiProfile(uid);
      hasSavedProfile = doc.exists;
    } catch (_) {}

    if (!mounted) return;

    if (hasSavedProfile) {
      _showProfileChoiceDialog(templateId);
    } else {
      _openAiSetupWizard(templateId);
    }
  }

  void _showProfileChoiceDialog(String templateId) async {
    // Load saved profile data
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    Map<String, dynamic>? profileData;
    try {
      final doc = await FirebaseService.getAiProfile(uid);
      if (doc.exists) profileData = doc.data() as Map<String, dynamic>;
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      barrierColor: AppColors.prussianBlue.withValues(alpha: 0.7),
      builder: (dialogContext) => Center(
        child: Container(
          width: 440,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.petalFrost,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.userCheck,
                  color: AppColors.darkRaspberry,
                  size: 22,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Welcome back!',
                style: TextStyle(
                  color: AppColors.prussianBlue,
                  fontSize: 17,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'We found your saved profile',
                style: TextStyle(
                  color: AppColors.slateGrey,
                  fontSize: 12,
                  fontFamily: AppFonts.openSans,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 20),

              // Profile summary card
              if (profileData != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 14, left: 14, bottom: 14, right: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF0EBE7)),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: (){
                            //todo
                          },
                          child: Icon(
                              LucideIcons.trash2,
                              size: 16,
                              color: AppColors.error,
                            ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((profileData['fullName'] ?? '').isNotEmpty)
                            _buildProfileRow(
                                LucideIcons.user, profileData['fullName']),
                          if ((profileData['email'] ?? '').isNotEmpty)
                            _buildProfileRow(
                                LucideIcons.mail, profileData['email']),
                          if ((profileData['jobTitle'] ?? '').isNotEmpty)
                            _buildProfileRow(
                                LucideIcons.briefcase, profileData['jobTitle']),
                          if ((profileData['industry'] ?? '').isNotEmpty)
                            _buildProfileRow(
                                LucideIcons.building2, profileData['industry']),
                          if ((profileData['experiences'] as List?)?.isNotEmpty ??
                              false)
                            _buildProfileRow(LucideIcons.award,
                                '${(profileData['experiences'] as List).length} work experiences'),
                          if ((profileData['education'] as List?)?.isNotEmpty ??
                              false)
                            _buildProfileRow(LucideIcons.graduationCap,
                                '${(profileData['education'] as List).length} education entries'),
                          if ((profileData['skills'] as List?)?.isNotEmpty ?? false)
                            _buildProfileRow(LucideIcons.sparkles,
                                '${(profileData['skills'] as List).length} skills'),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // Use saved profile
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    context.go('/cv/edit/$templateId');
                  },
                  icon: const Icon(LucideIcons.zap, size: 16),
                  label: const Text('Use Saved Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkRaspberry,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Edit details
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _openAiSetupWizard(templateId);
                  },
                  icon: const Icon(LucideIcons.pencil, size: 16),
                  label: const Text('Edit My Details'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.prussianBlue,
                    side: const BorderSide(color: AppColors.almondSilk),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Start fresh
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openAiSetupWizard(templateId);
                },
                child: const Text(
                  'Start from scratch',
                  style: TextStyle(
                    color: AppColors.slateGrey,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: AppColors.dustyMauve, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.prussianBlue,
                fontSize: 13,
                fontFamily: AppFonts.openSans,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _openAiSetupWizard(String templateId) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      builder: (dialogContext) => AiSetupPanel(
        onContinue: () {
          Navigator.pop(dialogContext);
          context.go('/cv/edit/$templateId');
        },
        onSkip: () {
          Navigator.pop(dialogContext);
          context.go('/cv/edit/$templateId');
        },
        onClose: () => Navigator.pop(dialogContext),
      ),
    );
  }
}