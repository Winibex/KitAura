// lib/features/ai_setup/view/ai_setup_panel.dart
//
// 8-step Career Profile setup wizard.
// Steps: Personal Info → Experience → Education → Skills/Languages/Certs
//        → Projects → Awards/Volunteer → References/Hobbies/Custom → AI Preferences

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/widgets/add_button.dart';
import '../../../shared/widgets/chip_input.dart';
import '../../../shared/widgets/pill_selector.dart';
import '../controller/ai_setup_controller.dart';

enum AiToolType { cv, proposal, coverLetter, linkedinSummary }

class AiSetupPanel extends ConsumerStatefulWidget {
  final AiToolType toolType;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onClose;
  final String? profileId;     // null = create new, non-null = edit existing
  final String? profileName;   // pre-fill name for new profiles
  final bool startFresh;

  const AiSetupPanel({
    super.key,
    required this.onContinue,
    required this.onSkip,
    required this.onClose,
    this.toolType = AiToolType.cv,
    this.profileId,
    this.profileName,
    this.startFresh = false,
  });

  @override
  ConsumerState<AiSetupPanel> createState() => _AiSetupPanelState();
}

class _AiSetupPanelState extends ConsumerState<AiSetupPanel> {
  // Step 1 controllers
  final _nameCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _linkedInCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _nationalityCtrl = TextEditingController();
  // Social links controllers
  final _githubCtrl = TextEditingController();
  final _twitterCtrl = TextEditingController();
  final _behanceCtrl = TextEditingController();
  final _dribbbleCtrl = TextEditingController();
  final _stackoverflowCtrl = TextEditingController();
  final _mediumCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _portfolioCtrl = TextEditingController();

  // Step 4 controllers
  final _skillCtrl = TextEditingController();
  final _languageCtrl = TextEditingController();

  // Step 7 controllers
  final _hobbyCtrl = TextEditingController();

  // Step 8 controllers
  final _jobTitleCtrl = TextEditingController();

  String _selectedProficiency = 'intermediate';
  String? _selectedGender;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (widget.startFresh) {
        // Don't load anything — start with empty profile
        ref.read(aiSetupControllerProvider.notifier).resetProfile();
      } else if (widget.profileId != null) {
        await ref.read(aiSetupControllerProvider.notifier)
            .loadProfileById(widget.profileId!);
      } else {
        await ref.read(aiSetupControllerProvider.notifier).loadProfile();
      }
      if (!mounted) return;
      _syncControllersFromProfile();
    });
  }

  void _syncControllersFromProfile() {
    final p = ref.read(aiSetupControllerProvider).profile;
    _nameCtrl.text = p.fullName;
    _companyCtrl.text = p.companyName;
    _emailCtrl.text = p.email;
    _phoneCtrl.text = p.phone;
    _locationCtrl.text = p.location;
    _linkedInCtrl.text = p.linkedIn ?? '';
    _websiteCtrl.text = p.website ?? '';
    _dobCtrl.text = p.dateOfBirth ?? '';
    _nationalityCtrl.text = p.nationality ?? '';
    _selectedGender = p.gender;
    _jobTitleCtrl.text = p.jobTitle ?? '';
    // Social links
    _githubCtrl.text = p.socialLinks.github ?? '';
    _twitterCtrl.text = p.socialLinks.twitter ?? '';
    _behanceCtrl.text = p.socialLinks.behance ?? '';
    _dribbbleCtrl.text = p.socialLinks.dribbble ?? '';
    _stackoverflowCtrl.text = p.socialLinks.stackoverflow ?? '';
    _mediumCtrl.text = p.socialLinks.medium ?? '';
    _youtubeCtrl.text = p.socialLinks.youtube ?? '';
    _portfolioCtrl.text = p.socialLinks.portfolio ?? '';
  }

  void _syncProfileFromControllers() {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    ctrl.updatePersonalInfo(
      fullName: _nameCtrl.text.trim(),
      companyName: _companyCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      linkedIn: _nullIfEmpty(_linkedInCtrl.text),
      website: _nullIfEmpty(_websiteCtrl.text),
      dateOfBirth: _nullIfEmpty(_dobCtrl.text),
      nationality: _nullIfEmpty(_nationalityCtrl.text),
      gender: _selectedGender,
    );
    ctrl.updateSocialLinks(
      SocialLinks(
        github: _nullIfEmpty(_githubCtrl.text),
        twitter: _nullIfEmpty(_twitterCtrl.text),
        behance: _nullIfEmpty(_behanceCtrl.text),
        dribbble: _nullIfEmpty(_dribbbleCtrl.text),
        stackoverflow: _nullIfEmpty(_stackoverflowCtrl.text),
        medium: _nullIfEmpty(_mediumCtrl.text),
        youtube: _nullIfEmpty(_youtubeCtrl.text),
        portfolio: _nullIfEmpty(_portfolioCtrl.text),
      ),
    );
  }

  String? _nullIfEmpty(String text) => text.trim().isEmpty ? null : text.trim();

  void _confirmClose() {
    final state = ref.read(aiSetupControllerProvider);
    final hasData =
        state.profile.fullName.isNotEmpty ||
            state.profile.experiences.isNotEmpty ||
            state.profile.education.isNotEmpty ||
            state.profile.skills.isNotEmpty;

    if (!hasData) {
      widget.onClose();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(LucideIcons.alertTriangle, size: 24,
                    color: AppColors.error.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Unsaved Changes',
                style: TextStyle(
                  fontSize: 18,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                  color: AppColors.prussianBlue,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You have changes that haven\'t been saved.\nWhat would you like to do?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(aiSetupControllerProvider.notifier).saveProfile();
                    if (mounted) widget.onClose();
                  },
                  icon: const Icon(LucideIcons.save, size: 15),
                  label: const Text('Save & Close'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.darkRaspberry,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onClose();
                  },
                  icon: const Icon(LucideIcons.trash2, size: 15),
                  label: const Text('Discard Changes'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Text(
                    'Keep editing',
                    style: TextStyle(
                      color: AppColors.slateGrey,
                      fontSize: 12,
                      fontFamily: AppFonts.openSans,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _generateLabel {
    switch (widget.toolType) {
      case AiToolType.cv:
        return 'Generate CV';
      case AiToolType.proposal:
        return 'Generate Proposal';
      case AiToolType.coverLetter:
        return 'Generate Cover Letter';
      case AiToolType.linkedinSummary:
        return 'Generate Summary';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _companyCtrl,
      _emailCtrl,
      _phoneCtrl,
      _locationCtrl,
      _linkedInCtrl,
      _websiteCtrl,
      _dobCtrl,
      _nationalityCtrl,
      _githubCtrl,
      _twitterCtrl,
      _behanceCtrl,
      _dribbbleCtrl,
      _stackoverflowCtrl,
      _mediumCtrl,
      _youtubeCtrl,
      _portfolioCtrl,
      _skillCtrl,
      _languageCtrl,
      _hobbyCtrl,
      _jobTitleCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _handleNext() async {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    final state = ref.read(aiSetupControllerProvider);

    if (state.currentStep == 0) _syncProfileFromControllers();
    if (state.currentStep == 7) {
      ctrl.updatePreferences(jobTitle: _jobTitleCtrl.text.trim());
    }

    if (state.isLastStep) {
      final success = await ctrl.saveProfile();
      if (success && mounted) widget.onContinue();
    } else {
      ctrl.nextStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiSetupControllerProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = screenWidth < 768 ? screenWidth : 520.0;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          GestureDetector(
            onTap: _confirmClose,
            child: Container(
              color: AppColors.prussianBlue.withValues(alpha: 0.5),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: panelWidth,
            child:
                Container(
                  color: AppColors.white,
                  child: Column(
                    children: [
                      _buildHeader(state),
                      _buildProgressBar(state),
                      Expanded(
                        child: state.isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.darkRaspberry,
                                ),
                              )
                            : AnimatedSwitcher(
                                duration: 200.ms,
                                transitionBuilder: (child, anim) =>
                                    FadeTransition(opacity: anim, child: child),
                                child: SingleChildScrollView(
                                  key: ValueKey(state.currentStep),
                                  padding: const EdgeInsets.all(28),
                                  child: _buildCurrentStep(state),
                                ),
                              ),
                      ),
                      _buildFooter(state),
                    ],
                  ),
                ).animate().slideX(
                  begin: 1,
                  end: 0,
                  duration: 300.ms,
                  curve: Curves.easeOut,
                ),
          ),
        ],
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────────────────

  Widget _buildHeader(AiSetupState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.petalFrost)),
      ),
      child: Row(
        children: [
          Image.asset(AppAssets.logoIconDark, height: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.stepTitle,
                  style: const TextStyle(
                    color: AppColors.prussianBlue,
                    fontSize: 16,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  state.stepSubtitle,
                  style: const TextStyle(
                    color: AppColors.slateGrey,
                    fontSize: 11,
                    fontFamily: AppFonts.openSans,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${state.currentStep + 1}/${AiSetupState.totalSteps}',
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 12,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _confirmClose,
            child: const Icon(
              LucideIcons.x,
              color: AppColors.slateGrey,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(AiSetupState state) {
    return Container(
      height: 3,
      color: AppColors.petalFrost,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedFractionallySizedBox(
          duration: 200.ms,
          widthFactor: state.progress,
          child: Container(color: AppColors.darkRaspberry),
        ),
      ),
    );
  }

  // ─── STEP ROUTER ───────────────────────────────────────────────────────

  Widget _buildCurrentStep(AiSetupState state) {
    switch (state.currentStep) {
      case 0:
        return _buildStep1PersonalInfo(state);
      case 1:
        return _buildStep2Experience(state);
      case 2:
        return _buildStep3Education(state);
      case 3:
        return _buildStep4Skills(state);
      case 4:
        return _buildStep5Projects(state);
      case 5:
        return _buildStep6AwardsVolunteer(state);
      case 6:
        return _buildStep7Additional(state);
      case 7:
        return _buildStep8Preferences(state);
      default:
        return const SizedBox.shrink();
    }
  }

  // ─── STEP 1: PERSONAL INFO ────────────────────────────────────────────

  Widget _buildStep1PersonalInfo(AiSetupState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField('Full Name', _nameCtrl, 'John Doe', true),
        _buildField('Company Name', _companyCtrl, 'Acme Corporation', false),
        _buildField('Email', _emailCtrl, 'john@example.com', true),
        _buildField('Phone', _phoneCtrl, '+1 234 567 8900', false),
        _buildField('Location', _locationCtrl, 'New York, USA', false),
        _buildField(
          'LinkedIn',
          _linkedInCtrl,
          'linkedin.com/in/johndoe',
          false,
        ),
        _buildField('Website', _websiteCtrl, 'johndoe.com', false),
        _buildField('Date of Birth', _dobCtrl, 'Jan 1, 1995', false),
        _buildField('Nationality', _nationalityCtrl, 'American', false),

        // Gender dropdown
        _buildLabel('Gender', false),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.almondSilk),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedGender,
              isExpanded: true,
              hint: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select',
                  style: TextStyle(color: AppColors.almondSilk),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              borderRadius: BorderRadius.circular(10),
              items: ['Male', 'Female', 'Prefer not to say']
                  .map(
                    (g) => DropdownMenuItem(
                      value: g.toLowerCase(),
                      child: Text(g),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _selectedGender = v),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Social Links (collapsible)
        _buildSectionHeader('Social Links', LucideIcons.link),
        const SizedBox(height: 12),
        _buildField('GitHub', _githubCtrl, 'github.com/username', false),
        _buildField('Twitter / X', _twitterCtrl, 'twitter.com/username', false),
        _buildField('Behance', _behanceCtrl, 'behance.net/username', false),
        _buildField('Dribbble', _dribbbleCtrl, 'dribbble.com/username', false),
        _buildField(
          'StackOverflow',
          _stackoverflowCtrl,
          'stackoverflow.com/users/id',
          false,
        ),
        _buildField('Medium', _mediumCtrl, 'medium.com/@username', false),
        _buildField('YouTube', _youtubeCtrl, 'youtube.com/@channel', false),
        _buildField(
          'Portfolio',
          _portfolioCtrl,
          'portfolio.example.com',
          false,
        ),
      ],
    );
  }

  // ─── STEP 2: WORK EXPERIENCE ──────────────────────────────────────────

  Widget _buildStep2Experience(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...state.profile.experiences.asMap().entries.map(
          (entry) => _buildExperienceCard(entry.key, entry.value, ctrl),
        ),
        const SizedBox(height: 12),
        addItemButton('Add Work Experience', () => ctrl.addExperience()),
        if (state.profile.experiences.isEmpty)
          _buildEmptyHint(
            'No experience added yet.\nAI will generate placeholder content.',
          ),
      ],
    );
  }

  Widget _buildExperienceCard(
    int index,
    WorkExperienceEntry exp,
    AiSetupController ctrl,
  )
  {
    return _buildCard(
      title: 'Experience ${index + 1}',
      onDelete: () => ctrl.removeExperience(index),
      children: [
        _buildCardField(
          'Job Title',
          exp.jobTitle,
          (v) => ctrl.updateExperience(index, exp.copyWith(jobTitle: v)),
        ),
        _buildCardField(
          'Company',
          exp.company,
          (v) => ctrl.updateExperience(index, exp.copyWith(company: v)),
        ),
        Row(
          children: [
            Expanded(
              child: _buildCardField(
                'Start Date',
                exp.startDate,
                (v) => ctrl.updateExperience(index, exp.copyWith(startDate: v)),
                hint: 'Jan 2022',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardField(
                'End Date',
                exp.isCurrentRole ? 'Present' : exp.endDate,
                (v) => ctrl.updateExperience(index, exp.copyWith(endDate: v)),
                hint: 'Dec 2024',
                enabled: !exp.isCurrentRole,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Checkbox(
              value: exp.isCurrentRole,
              onChanged: (v) => ctrl.updateExperience(
                index,
                exp.copyWith(isCurrentRole: v ?? false),
              ),
              activeColor: AppColors.darkRaspberry,
              visualDensity: VisualDensity.compact,
            ),
            const Text(
              'Currently working here',
              style: TextStyle(
                color: AppColors.slateGrey,
                fontSize: 12,
                fontFamily: AppFonts.openSans,
              ),
            ),
          ],
        ),
        _buildCardField(
          'Description',
          exp.description,
          (v) => ctrl.updateExperience(index, exp.copyWith(description: v)),
          maxLines: 3,
          hint: 'Describe your responsibilities...',
        ),
      ],
    );
  }

  // ─── STEP 3: EDUCATION ────────────────────────────────────────────────

  Widget _buildStep3Education(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...state.profile.education.asMap().entries.map(
          (entry) => _buildEducationCard(entry.key, entry.value, ctrl),
        ),
        const SizedBox(height: 12),
        addItemButton('Add Education', () => ctrl.addEducation()),
        if (state.profile.education.isEmpty)
          _buildEmptyHint(
            'No education added yet.\nAI will generate placeholder content.',
          ),
      ],
    );
  }

  Widget _buildEducationCard(
    int index,
    EducationEntry edu,
    AiSetupController ctrl,
  )
  {
    return _buildCard(
      title: 'Education ${index + 1}',
      onDelete: () => ctrl.removeEducation(index),
      children: [
        _buildCardField(
          'Degree',
          edu.degree,
          (v) => ctrl.updateEducation(index, edu.copyWith(degree: v)),
          hint: 'Bachelor of Science',
        ),
        _buildCardField(
          'Field of Study',
          edu.fieldOfStudy,
          (v) => ctrl.updateEducation(index, edu.copyWith(fieldOfStudy: v)),
          hint: 'Computer Science',
        ),
        _buildCardField(
          'School / University',
          edu.school,
          (v) => ctrl.updateEducation(index, edu.copyWith(school: v)),
        ),
        Row(
          children: [
            Expanded(
              child: _buildCardField(
                'Start',
                edu.startDate,
                (v) => ctrl.updateEducation(index, edu.copyWith(startDate: v)),
                hint: '2018',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardField(
                'End',
                edu.endDate,
                (v) => ctrl.updateEducation(index, edu.copyWith(endDate: v)),
                hint: '2022',
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Grade Type',
                    style: TextStyle(
                      color: AppColors.slateGrey,
                      fontSize: 11,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.almondSilk),
                      borderRadius: BorderRadius.circular(8),
                      color: AppColors.white,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: edu.gradeType,
                        isExpanded: true,
                        hint: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Select',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.almondSilk,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        borderRadius: BorderRadius.circular(8),
                        items: ['gpa', 'cgpa', 'percentage', 'marks', 'grade']
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  _gradeLabel(t),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => ctrl.updateEducation(
                          index,
                          edu.copyWith(gradeType: v ?? ''),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: _buildCardField(
                'Grade Value',
                edu.gradeValue ?? '',
                (v) => ctrl.updateEducation(index, edu.copyWith(gradeValue: v)),
                hint: edu.gradeType == 'gpa'
                    ? '3.8/4.0'
                    : edu.gradeType == 'percentage'
                    ? '85%'
                    : 'Enter value',
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _gradeLabel(String? type) {
    switch (type) {
      case 'gpa':
        return 'GPA';
      case 'cgpa':
        return 'CGPA';
      case 'percentage':
        return 'Percentage';
      case 'marks':
        return 'Marks';
      case 'grade':
        return 'Grade';
      default:
        return 'Select';
    }
  }

  // ─── STEP 4: SKILLS, LANGUAGES, CERTIFICATIONS ───────────────────────

  Widget _buildStep4Skills(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Skills', false),
        const SizedBox(height: 8),
        chipInput(
          controller: _skillCtrl,
          hint: 'Type a skill and press Enter',
          items: state.profile.skills,
          onAdd: () {
            ctrl.addSkill(_skillCtrl.text);
            _skillCtrl.clear();
          },
          onRemove: (s) => ctrl.removeSkill(s),
        ),
        const SizedBox(height: 28),

        _buildLabel('Languages', false),
        const SizedBox(height: 8),
        ...state.profile.languages.asMap().entries.map((entry) {
          final lang = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.lavenderBlush,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.petalFrost),
            ),
            child: Row(
              children: [
                Text(
                  lang.language,
                  style: const TextStyle(
                    color: AppColors.prussianBlue,
                    fontSize: 13,
                    fontFamily: AppFonts.poppins,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.petalFrost,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    lang.proficiency[0].toUpperCase() +
                        lang.proficiency.substring(1),
                    style: const TextStyle(
                      color: AppColors.darkRaspberry,
                      fontSize: 11,
                      fontFamily: AppFonts.poppins,
                    ),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => ctrl.removeLanguage(entry.key),
                  child: const Icon(
                    LucideIcons.x,
                    color: AppColors.slateGrey,
                    size: 16,
                  ),
                ),
              ],
            ),
          );
        }),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _languageCtrl,
                decoration: InputDecoration(
                  hintText: 'Language',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.almondSilk),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedProficiency,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    borderRadius: BorderRadius.circular(10),
                    items: ['native', 'fluent', 'intermediate', 'beginner']
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              p[0].toUpperCase() + p.substring(1),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedProficiency = v);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  if (_languageCtrl.text.trim().isNotEmpty) {
                    ctrl.addLanguage(
                      _languageCtrl.text.trim(),
                      _selectedProficiency,
                    );
                    _languageCtrl.clear();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.darkRaspberry,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: Size.zero,
                ),
                child: const Icon(
                  LucideIcons.plus,
                  color: AppColors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        _buildLabel('Certifications', false),
        const SizedBox(height: 8),
        ...state.profile.certifications.asMap().entries.map(
          (entry) => _buildCertificationCard(entry.key, entry.value, ctrl),
        ),
        const SizedBox(height: 8),
        addItemButton('Add Certification', () => ctrl.addCertification()),
      ],
    );
  }

  Widget _buildCertificationCard(
    int index,
    CertificationEntry cert,
    AiSetupController ctrl,
  )
  {
    return _buildCard(
      title: 'Certification ${index + 1}',
      onDelete: () => ctrl.removeCertification(index),
      children: [
        _buildCardField(
          'Name',
          cert.name,
          (v) => ctrl.updateCertification(index, cert.copyWith(name: v)),
          hint: 'AWS Solutions Architect',
        ),
        _buildCardField(
          'Issuing Organization',
          cert.institute ?? '',
          (v) => ctrl.updateCertification(index, cert.copyWith(institute: v)),
          hint: 'Amazon Web Services',
        ),
        Row(
          children: [
            Expanded(
              child: _buildCardField(
                'Issue Date',
                cert.issueDate ?? '',
                (v) => ctrl.updateCertification(
                  index,
                  cert.copyWith(issueDate: v),
                ),
                hint: 'Jan 2024',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardField(
                'Expiry Date',
                cert.expiryDate ?? '',
                (v) => ctrl.updateCertification(
                  index,
                  cert.copyWith(expiryDate: v),
                ),
                hint: 'Jan 2027',
              ),
            ),
          ],
        ),
        _buildCardField(
          'Credential ID',
          cert.credentialId ?? '',
          (v) =>
              ctrl.updateCertification(index, cert.copyWith(credentialId: v)),
          hint: 'ABC-123',
        ),
        _buildCardField(
          'Credential URL',
          cert.credentialUrl ?? '',
          (v) =>
              ctrl.updateCertification(index, cert.copyWith(credentialUrl: v)),
          hint: 'https://verify.example.com/...',
        ),
      ],
    );
  }

  // ─── STEP 5: PROJECTS ────────────────────────────────────────────────

  Widget _buildStep5Projects(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...state.profile.projects.asMap().entries.map(
          (entry) => _buildProjectCard(entry.key, entry.value, ctrl),
        ),
        const SizedBox(height: 12),
        addItemButton('Add Project', () => ctrl.addProject()),
        if (state.profile.projects.isEmpty)
          _buildEmptyHint(
            'No projects added yet.\nShowcase your best work here.',
          ),
      ],
    );
  }

  Widget _buildProjectCard(
    int index,
    ProjectEntry proj,
    AiSetupController ctrl,
  )
  {
    return _buildCard(
      title: 'Project ${index + 1}',
      onDelete: () => ctrl.removeProject(index),
      children: [
        _buildCardField(
          'Project Name',
          proj.name,
          (v) => ctrl.updateProject(index, proj.copyWith(name: v)),
          hint: 'E-commerce Platform',
        ),
        _buildCardField(
          'Description',
          proj.description,
          (v) => ctrl.updateProject(index, proj.copyWith(description: v)),
          hint: 'Describe what you built...',
          maxLines: 3,
        ),
        _buildCardField(
          'URL',
          proj.url ?? '',
          (v) => ctrl.updateProject(index, proj.copyWith(url: v)),
          hint: 'https://github.com/...',
        ),
        Row(
          children: [
            Expanded(
              child: _buildCardField(
                'Start',
                proj.startDate,
                (v) => ctrl.updateProject(index, proj.copyWith(startDate: v)),
                hint: 'Jan 2024',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardField(
                'End',
                proj.endDate,
                (v) => ctrl.updateProject(index, proj.copyWith(endDate: v)),
                hint: 'Jun 2024',
              ),
            ),
          ],
        ),
        _buildCardField(
          'Tech Stack (comma separated)',
          proj.techStack.join(', '),
          (v) {
            ctrl.updateProject(
              index,
              proj.copyWith(
                techStack: v
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
              ),
            );
          },
          hint: 'Flutter, Firebase, Node.js',
        ),
      ],
    );
  }

  // ─── STEP 6: AWARDS & VOLUNTEER ──────────────────────────────────────

  Widget _buildStep6AwardsVolunteer(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Awards & Honors', LucideIcons.award),
        const SizedBox(height: 12),
        ...state.profile.awards.asMap().entries.map(
          (entry) => _buildAwardCard(entry.key, entry.value, ctrl),
        ),
        addItemButton('Add Award', () => ctrl.addAward()),

        const SizedBox(height: 28),
        _buildSectionHeader('Volunteer Experience', LucideIcons.heart),
        const SizedBox(height: 12),
        ...state.profile.volunteerExperience.asMap().entries.map(
          (entry) => _buildVolunteerCard(entry.key, entry.value, ctrl),
        ),
        addItemButton('Add Volunteer Experience', () => ctrl.addVolunteer()),
      ],
    );
  }

  Widget _buildAwardCard(int index, AwardEntry award, AiSetupController ctrl) {
    return _buildCard(
      title: 'Award ${index + 1}',
      onDelete: () => ctrl.removeAward(index),
      children: [
        _buildCardField(
          'Title',
          award.title,
          (v) => ctrl.updateAward(index, award.copyWith(title: v)),
          hint: 'Employee of the Year',
        ),
        _buildCardField(
          'Issuer',
          award.issuer ?? '',
          (v) => ctrl.updateAward(index, award.copyWith(issuer: v)),
          hint: 'Google',
        ),
        _buildCardField(
          'Date',
          award.date ?? '',
          (v) => ctrl.updateAward(index, award.copyWith(date: v)),
          hint: '2024',
        ),
        _buildCardField(
          'Description',
          award.description ?? '',
          (v) => ctrl.updateAward(index, award.copyWith(description: v)),
          hint: 'Brief description...',
          maxLines: 2,
        ),
      ],
    );
  }

  Widget _buildVolunteerCard(
    int index,
    VolunteerEntry vol,
    AiSetupController ctrl,
  )
  {
    return _buildCard(
      title: 'Volunteer ${index + 1}',
      onDelete: () => ctrl.removeVolunteer(index),
      children: [
        _buildCardField(
          'Role',
          vol.role,
          (v) => ctrl.updateVolunteer(index, vol.copyWith(role: v)),
          hint: 'Event Coordinator',
        ),
        _buildCardField(
          'Organization',
          vol.organization,
          (v) => ctrl.updateVolunteer(index, vol.copyWith(organization: v)),
          hint: 'Red Cross',
        ),
        Row(
          children: [
            Expanded(
              child: _buildCardField(
                'Start',
                vol.startDate,
                (v) => ctrl.updateVolunteer(index, vol.copyWith(startDate: v)),
                hint: 'Jan 2023',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardField(
                'End',
                vol.endDate,
                (v) => ctrl.updateVolunteer(index, vol.copyWith(endDate: v)),
                hint: 'Dec 2023',
              ),
            ),
          ],
        ),
        _buildCardField(
          'Description',
          vol.description,
          (v) => ctrl.updateVolunteer(index, vol.copyWith(description: v)),
          hint: 'What did you do?',
          maxLines: 2,
        ),
      ],
    );
  }

  // ─── STEP 7: REFERENCES, HOBBIES, CUSTOM ─────────────────────────────

  Widget _buildStep7Additional(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('References', LucideIcons.users),
        const SizedBox(height: 12),
        ...state.profile.references.asMap().entries.map(
          (entry) => _buildReferenceCard(entry.key, entry.value, ctrl),
        ),
        addItemButton('Add Reference', () => ctrl.addReference()),

        const SizedBox(height: 28),
        _buildLabel('Hobbies & Interests', false),
        const SizedBox(height: 8),
        chipInput(
          controller: _hobbyCtrl,
          hint: 'Type a hobby and press Enter',
          items: state.profile.hobbies,
          onAdd: () {
            ctrl.addHobby(_hobbyCtrl.text);
            _hobbyCtrl.clear();
          },
          onRemove: (s) => ctrl.removeHobby(s),
        ),

        const SizedBox(height: 28),
        _buildSectionHeader('Custom Sections', LucideIcons.layoutList),
        const SizedBox(height: 12),
        ...state.profile.customSections.asMap().entries.map(
          (entry) => _buildCustomSectionCard(entry.key, entry.value, ctrl),
        ),
        addItemButton('Add Custom Section', () => ctrl.addCustomSection()),
      ],
    );
  }

  Widget _buildReferenceCard(
    int index,
    ReferenceEntry ref_,
    AiSetupController ctrl,
  )
  {
    return _buildCard(
      title: 'Reference ${index + 1}',
      onDelete: () => ctrl.removeReference(index),
      children: [
        _buildCardField(
          'Name',
          ref_.name,
          (v) => ctrl.updateReference(index, ref_.copyWith(name: v)),
          hint: 'Jane Smith',
        ),
        _buildCardField(
          'Relationship',
          ref_.relationship ?? '',
          (v) => ctrl.updateReference(index, ref_.copyWith(relationship: v)),
          hint: 'Former Manager',
        ),
        _buildCardField(
          'Company',
          ref_.company ?? '',
          (v) => ctrl.updateReference(index, ref_.copyWith(company: v)),
          hint: 'Google',
        ),
        Row(
          children: [
            Expanded(
              child: _buildCardField(
                'Email',
                ref_.email ?? '',
                (v) => ctrl.updateReference(index, ref_.copyWith(email: v)),
                hint: 'jane@example.com',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCardField(
                'Phone',
                ref_.phone ?? '',
                (v) => ctrl.updateReference(index, ref_.copyWith(phone: v)),
                hint: '+1 234 567',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCustomSectionCard(
    int index,
    CustomSection section,
    AiSetupController ctrl,
  )
  {
    return _buildCard(
      title: 'Custom Section ${index + 1}',
      onDelete: () => ctrl.removeCustomSection(index),
      children: [
        _buildCardField(
          'Section Title',
          section.title,
          (v) => ctrl.updateCustomSection(index, section.copyWith(title: v)),
          hint: 'Publications',
        ),
        _buildCardField(
          'Content',
          section.content,
          (v) => ctrl.updateCustomSection(index, section.copyWith(content: v)),
          hint: 'Enter content...',
          maxLines: 4,
        ),
      ],
    );
  }

  // ─── STEP 8: AI PREFERENCES ──────────────────────────────────────────

  Widget _buildStep8Preferences(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Target Job Title', true),
        const SizedBox(height: 8),
        TextField(
          controller: _jobTitleCtrl,
          decoration: InputDecoration(
            hintText: 'e.g. Senior Software Engineer',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 24),

        _buildLabel('Experience Level', false),
        const SizedBox(height: 8),
        pillSelector(
          options: ['junior', 'mid', 'senior', 'executive'],
          labels: ['Junior', 'Mid', 'Senior', 'Executive'],
          selected: state.profile.experienceLevel,
          onSelect: (v) => ctrl.updatePreferences(experienceLevel: v),
        ),
        const SizedBox(height: 24),

        _buildLabel('Industry', false),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.almondSilk),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: state.profile.industry.isEmpty
                  ? null
                  : state.profile.industry,
              isExpanded: true,
              hint: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select industry',
                  style: TextStyle(color: AppColors.almondSilk),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              borderRadius: BorderRadius.circular(10),
              items: [
                'Technology',
                'Finance',
                'Healthcare',
                'Marketing',
                'Design',
                'Education',
                'Engineering',
                'Legal',
                'Other',
              ].map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
              onChanged: (v) {
                if (v != null) ctrl.updatePreferences(industry: v);
              },
            ),
          ),
        ),
        const SizedBox(height: 24),

        _buildLabel('Writing Tone', false),
        const SizedBox(height: 8),
        pillSelector(
          options: ['professional', 'creative', 'concise'],
          labels: ['Professional', 'Creative', 'Concise'],
          selected: state.profile.tone,
          onSelect: (v) => ctrl.updatePreferences(tone: v),
        ),
        const SizedBox(height: 24),

        // Summary
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.petalFrost,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.almondSilk),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    color: AppColors.darkRaspberry,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'AI will generate content based on:',
                    style: TextStyle(
                      color: AppColors.prussianBlue,
                      fontSize: 13,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _summaryRow('Experiences', '${state.profile.experiences.length}'),
              _summaryRow('Education', '${state.profile.education.length}'),
              _summaryRow('Skills', '${state.profile.skills.length}'),
              _summaryRow('Languages', '${state.profile.languages.length}'),
              _summaryRow(
                'Certifications',
                '${state.profile.certifications.length}',
              ),
              _summaryRow('Projects', '${state.profile.projects.length}'),
              _summaryRow('Awards', '${state.profile.awards.length}'),
              _summaryRow(
                'Volunteer',
                '${state.profile.volunteerExperience.length}',
              ),
              _summaryRow('References', '${state.profile.references.length}'),
              _summaryRow('Hobbies', '${state.profile.hobbies.length}'),
            ],
          ),
        ),

        if (state.error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              state.error!,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 12,
              fontFamily: AppFonts.openSans,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.prussianBlue,
              fontSize: 12,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── FOOTER ────────────────────────────────────────────────────────────

  Widget _buildFooter(AiSetupState state) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.petalFrost)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (!state.isFirstStep)
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(aiSetupControllerProvider.notifier)
                          .previousStep(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.almondSilk),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Back',
                        style: TextStyle(color: AppColors.prussianBlue),
                      ),
                    ),
                  ),
                ),
              if (!state.isFirstStep) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: state.isSaving ? null : _handleNext,
                    child: state.isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(state.isLastStep ? _generateLabel : 'Continue'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: widget.onSkip,
            child: const Text(
              'Skip for now',
              style: TextStyle(color: AppColors.slateGrey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _confirmDeleteProfile,
            icon: const Icon(
              LucideIcons.trash2,
              size: 14,
              color: AppColors.error,
            ),
            label: const Text(
              'Delete Profile',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // FIND and REPLACE _confirmDeleteProfile():

  void _confirmDeleteProfile() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(LucideIcons.trash2, size: 24, color: AppColors.error),
              ),
              const SizedBox(height: 20),
              const Text(
                'Delete Profile?',
                style: TextStyle(
                  fontSize: 18,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.bold,
                  color: AppColors.prussianBlue,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This will permanently delete all your saved profile data. This action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppFonts.openSans,
                  color: AppColors.slateGrey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(aiSetupControllerProvider.notifier).deleteProfile();
                    if (mounted) {
                      _syncControllersFromProfile();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile deleted'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.trash2, size: 15),
                  label: const Text('Delete Forever'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontFamily: AppFonts.poppins,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.slateGrey,
                      fontSize: 12,
                      fontFamily: AppFonts.openSans,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── REUSABLE WIDGETS ──────────────────────────────────────────────────

  Widget _buildCard({
    required String title,
    required VoidCallback onDelete,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lavenderBlush,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.petalFrost),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.prussianBlue,
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(
                  LucideIcons.trash2,
                  color: AppColors.error,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl,
    String hint,
    bool required,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel(label, required),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardField(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    String? hint,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slateGrey,
              fontSize: 11,
              fontFamily: AppFonts.poppins,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: value,
            enabled: enabled,
            maxLines: maxLines,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint ?? label,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text, bool required) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: AppColors.prussianBlue,
            fontSize: 13,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(color: AppColors.error, fontSize: 13),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.darkRaspberry),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.prussianBlue,
            fontSize: 15,
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.slateGrey,
            fontSize: 13,
            fontFamily: AppFonts.openSans,
          ),
        ),
      ),
    );
  }
}
