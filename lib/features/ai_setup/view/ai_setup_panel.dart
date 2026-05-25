import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_fonts.dart';
import '../../../shared/models/education_entry.dart';
import '../../../shared/models/work_experience_entry.dart';
import '../../../shared/widgets/add_button.dart';
import '../../../shared/widgets/chip_input.dart';
import '../../../shared/widgets/pill_selector.dart';
import '../controller/ai_setup_controller.dart';
import '../../../shared/models/certification_entry.dart';

enum AiToolType { cv, proposal, coverLetter, linkedinSummary }

class AiSetupPanel extends ConsumerStatefulWidget {
  final AiToolType toolType;
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final VoidCallback onClose;

  const AiSetupPanel({
    super.key,
    required this.onContinue,
    required this.onSkip,
    required this.onClose,
    this.toolType = AiToolType.cv,  // ← default to CV for now
  });

  @override
  ConsumerState<AiSetupPanel> createState() => _AiSetupPanelState();
}

class _AiSetupPanelState extends ConsumerState<AiSetupPanel> {
  // Step 1 controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _linkedInCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();

  // Step 4 controllers
  final _skillCtrl = TextEditingController();
  final _languageCtrl = TextEditingController();
  final _certCtrl = TextEditingController();

  // Step 5 controllers
  final _jobTitleCtrl = TextEditingController();

  String _selectedProficiency = 'intermediate';

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(aiSetupControllerProvider.notifier).loadProfile();
      if (!mounted) return;
      _syncControllersFromProfile();
    });
  }

  void _syncControllersFromProfile() {
    final p = ref.read(aiSetupControllerProvider).profile;
    _nameCtrl.text = p.fullName;
    _emailCtrl.text = p.email;
    _phoneCtrl.text = p.phone;
    _locationCtrl.text = p.location;
    _linkedInCtrl.text = p.linkedIn ?? '';
    _websiteCtrl.text = p.website ?? '';
    _jobTitleCtrl.text = p.jobTitle ?? '';
  }

  void _syncProfileFromControllers() {
    ref.read(aiSetupControllerProvider.notifier).updatePersonalInfo(
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      linkedIn: _linkedInCtrl.text.trim().isEmpty
          ? null
          : _linkedInCtrl.text.trim(),
      website: _websiteCtrl.text.trim().isEmpty
          ? null
          : _websiteCtrl.text.trim(),
    );
  }

  void _confirmClose() {
    final state = ref.read(aiSetupControllerProvider);
    final hasData = state.profile.fullName.isNotEmpty ||
        state.profile.experiences.isNotEmpty ||
        state.profile.education.isNotEmpty ||
        state.profile.skills.isNotEmpty;

    if (!hasData) {
      widget.onClose();
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Discard changes?',
          style: TextStyle(
            fontFamily: AppFonts.poppins,
            fontWeight: FontWeight.bold,
            color: AppColors.prussianBlue,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'You have unsaved information. Do you want to save before closing?',
          style: TextStyle(
            fontFamily: AppFonts.openSans,
            color: AppColors.slateGrey,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onClose();
            },
            child: const Text(
              'Discard',
              style: TextStyle(color: AppColors.error),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(aiSetupControllerProvider.notifier).saveProfile();
              if (mounted) widget.onClose();
            },
            child: const Text('Save & Close'),
          ),
        ],
      ),
    );
  }

  String get _generateLabel {
    switch (widget.toolType) {
      case AiToolType.cv:              return 'Generate CV';
      case AiToolType.proposal:        return 'Generate Proposal';
      case AiToolType.coverLetter:     return 'Generate Cover Letter';
      case AiToolType.linkedinSummary: return 'Generate Summary';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    _linkedInCtrl.dispose();
    _websiteCtrl.dispose();
    _skillCtrl.dispose();
    _languageCtrl.dispose();
    _certCtrl.dispose();
    _jobTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    final state = ref.read(aiSetupControllerProvider);

    // Sync text fields on step 1
    if (state.currentStep == 0) _syncProfileFromControllers();

    // Sync job title on step 5
    if (state.currentStep == 4) {
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
    final panelWidth = screenWidth < 768 ? screenWidth : 480.0;

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
            child: Container(
              color: AppColors.white,
              child: Column(
                children: [
                  _buildHeader(state),
                  _buildProgressBar(state),
                  Expanded(
                    child: state.isLoading
                        ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.darkRaspberry),
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
            child: const Icon(LucideIcons.x, color: AppColors.slateGrey, size: 20),
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
        return _buildStep5Preferences(state);
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
        _buildField('Email', _emailCtrl, 'john@example.com', true),
        _buildField('Phone', _phoneCtrl, '+1 234 567 8900', false),
        _buildField('Location', _locationCtrl, 'New York, USA', false),
        _buildField('LinkedIn', _linkedInCtrl, 'linkedin.com/in/johndoe', false),
        _buildField('Website', _websiteCtrl, 'johndoe.com', false),
      ],
    );
  }

  // ─── STEP 2: WORK EXPERIENCE ──────────────────────────────────────────

  Widget _buildStep2Experience(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...state.profile.experiences.asMap().entries.map((entry) {
          return _buildExperienceCard(entry.key, entry.value, ctrl);
        }),
        const SizedBox(height: 12),
        addItemButton('Add Work Experience', () => ctrl.addExperience()),
        if (state.profile.experiences.isEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Text(
              'No experience added yet.\nYou can skip this and AI will generate placeholder content.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.slateGrey,
                fontSize: 13,
                fontFamily: AppFonts.openSans,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExperienceCard(
      int index, WorkExperienceEntry exp, AiSetupController ctrl) {
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
                'Experience ${index + 1}',
                style: const TextStyle(
                  color: AppColors.prussianBlue,
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ctrl.removeExperience(index),
                child: const Icon(LucideIcons.trash2,
                    color: AppColors.error, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCardField('Job Title', exp.jobTitle, (v) {
            ctrl.updateExperience(index, exp.copyWith(jobTitle: v));
          }),
          _buildCardField('Company', exp.company, (v) {
            ctrl.updateExperience(index, exp.copyWith(company: v));
          }),
          Row(
            children: [
              Expanded(
                child: _buildCardField('Start Date', exp.startDate, (v) {
                  ctrl.updateExperience(index, exp.copyWith(startDate: v));
                }, hint: 'Jan 2022'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCardField('End Date',
                    exp.isCurrentRole ? 'Present' : exp.endDate, (v) {
                      ctrl.updateExperience(index, exp.copyWith(endDate: v));
                    }, hint: 'Dec 2024', enabled: !exp.isCurrentRole),
              ),
            ],
          ),
          Row(
            children: [
              Checkbox(
                value: exp.isCurrentRole,
                onChanged: (v) {
                  ctrl.updateExperience(
                      index, exp.copyWith(isCurrentRole: v ?? false));
                },
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
          _buildCardField('Description', exp.description, (v) {
            ctrl.updateExperience(index, exp.copyWith(description: v));
          }, maxLines: 3, hint: 'Describe your responsibilities...'),
        ],
      ),
    );
  }

  // ─── STEP 3: EDUCATION ────────────────────────────────────────────────

  Widget _buildStep3Education(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...state.profile.education.asMap().entries.map((entry) {
          return _buildEducationCard(entry.key, entry.value, ctrl);
        }),
        const SizedBox(height: 12),
        addItemButton('Add Education', () => ctrl.addEducation()),
        if (state.profile.education.isEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Text(
              'No education added yet.\nAI will generate placeholder content.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.slateGrey,
                fontSize: 13,
                fontFamily: AppFonts.openSans,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEducationCard(int index, EducationEntry edu, AiSetupController ctrl) {
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
                'Education ${index + 1}',
                style: const TextStyle(
                  color: AppColors.prussianBlue,
                  fontSize: 13,
                  fontFamily: AppFonts.poppins,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ctrl.removeEducation(index),
                child: const Icon(LucideIcons.trash2,
                    color: AppColors.error, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCardField('Degree', edu.degree, (v) {
            ctrl.updateEducation(index, edu.copyWith(degree: v));
          }, hint: 'Bachelor of Science'),
          _buildCardField('Field of Study', edu.fieldOfStudy ?? '', (v) {
            ctrl.updateEducation(index, edu.copyWith(fieldOfStudy: v));
          }, hint: 'Computer Science'),
          _buildCardField('School / University', edu.school, (v) {
            ctrl.updateEducation(index, edu.copyWith(school: v));
          }),
          Row(
            children: [
              Expanded(
                child: _buildCardField('Start Date', edu.startDate, (v) {
                  ctrl.updateEducation(index, edu.copyWith(startDate: v));
                }, hint: '2018'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCardField('End Date', edu.endDate, (v) {
                  ctrl.updateEducation(index, edu.copyWith(endDate: v));
                }, hint: '2022'),
              ),
            ],
          ),
          // Grade type dropdown + value
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Grade Type',
                        style: TextStyle(color: AppColors.slateGrey,
                            fontSize: 11, fontFamily: AppFonts.poppins,
                            fontWeight: FontWeight.w500)),
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
                            child: Text('Select', style: TextStyle(fontSize: 12, color: AppColors.almondSilk)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          borderRadius: BorderRadius.circular(8),
                          items: EducationEntry.gradeTypes.map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(EducationEntry.gradeTypeLabel(t), style: const TextStyle(fontSize: 13)),
                          )).toList(),
                          onChanged: (v) {
                            ctrl.updateEducation(index, edu.copyWith(gradeType: v ?? ''));
                          },
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
                  edu.gradeType != null ? EducationEntry.gradeTypeLabel(edu.gradeType) : 'Grade Value',
                  edu.gradeValue ?? '',
                      (v) => ctrl.updateEducation(index, edu.copyWith(gradeValue: v)),
                  hint: edu.gradeType == 'gpa' ? '3.8 / 4.0'
                      : edu.gradeType == 'marks' ? '919 / 1100'
                      : edu.gradeType == 'percentage' ? '85%'
                      : edu.gradeType == 'cgpa' ? '3.5 / 4.0'
                      : edu.gradeType == 'grade' ? 'A+'
                      : 'Enter value',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── STEP 4: SKILLS & LANGUAGES ───────────────────────────────────────

  Widget _buildStep4Skills(AiSetupState state) {
    final ctrl = ref.read(aiSetupControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Skills
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

        // Languages
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
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                  child: const Icon(LucideIcons.x,
                      color: AppColors.slateGrey, size: 16),
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
                      horizontal: 14, vertical: 12),
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
                        .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                        p[0].toUpperCase() + p.substring(1),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ))
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
                        _languageCtrl.text.trim(), _selectedProficiency);
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
                child: const Icon(LucideIcons.plus,
                    color: AppColors.white, size: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Certifications (structured)
        _buildLabel('Certifications', false),
        const SizedBox(height: 8),
        ...state.profile.certifications.asMap().entries.map((entry) {
          return _buildCertificationCard(entry.key, entry.value, ctrl);
        }),
        const SizedBox(height: 8),
        addItemButton('Add Certification', () => ctrl.addCertification()),
      ],
    );
  }

  Widget _buildCertificationCard(
      int index, CertificationEntry cert, AiSetupController ctrl) {
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
                'Certification ${index + 1}',
                style: const TextStyle(
                  color: AppColors.prussianBlue, fontSize: 13,
                  fontFamily: AppFonts.poppins, fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ctrl.removeCertification(index),
                child: const Icon(LucideIcons.trash2, color: AppColors.error, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCardField('Certification Name', cert.name, (v) {
            ctrl.updateCertification(index, cert.copyWith(name: v));
          }, hint: 'AWS Solutions Architect'),
          _buildCardField('Issuing Organization', cert.institute ?? '', (v) {
            ctrl.updateCertification(index, cert.copyWith(institute: v));
          }, hint: 'Amazon Web Services'),
          Row(
            children: [
              Expanded(child: _buildCardField('Issue Date', cert.issueDate ?? '', (v) {
                ctrl.updateCertification(index, cert.copyWith(issueDate: v));
              }, hint: 'Jan 2024')),
              const SizedBox(width: 12),
              Expanded(child: _buildCardField('Expiry Date', cert.expiryDate ?? '', (v) {
                ctrl.updateCertification(index, cert.copyWith(expiryDate: v));
              }, hint: 'Jan 2027 (or leave empty)')),
            ],
          ),
          _buildCardField('Credential ID', cert.credentialId ?? '', (v) {
            ctrl.updateCertification(index, cert.copyWith(credentialId: v));
          }, hint: 'ABC-123-XYZ'),
          _buildCardField('Credential URL', cert.credentialUrl ?? '', (v) {
            ctrl.updateCertification(index, cert.copyWith(credentialUrl: v));
          }, hint: 'https://verify.example.com/...'),
        ],
      ),
    );
  }

  // ─── STEP 5: AI PREFERENCES ───────────────────────────────────────────

  Widget _buildStep5Preferences(AiSetupState state) {
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
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
                child: Text('Select industry',
                    style: TextStyle(color: AppColors.almondSilk)),
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
                'Other'
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
                  Icon(LucideIcons.sparkles,
                      color: AppColors.darkRaspberry, size: 16),
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
              _buildSummaryRow('Experiences',
                  '${state.profile.experiences.length} entries'),
              _buildSummaryRow('Education',
                  '${state.profile.education.length} entries'),
              _buildSummaryRow(
                  'Skills', '${state.profile.skills.length} skills'),
              _buildSummaryRow('Languages',
                  '${state.profile.languages.length} languages'),
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
            child: Text(state.error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
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
            onPressed: () => _confirmDeleteProfile(),
            icon: const Icon(LucideIcons.trash2, size: 14, color: AppColors.error),
            label: const Text(
              'Delete Profile',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteProfile() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Profile?',
            style: TextStyle(fontFamily: AppFonts.poppins,
                fontWeight: FontWeight.bold, color: AppColors.prussianBlue)),
        content: const Text(
          'This will permanently delete all your saved profile data '
              '(experiences, education, skills, etc.). This cannot be undone.',
          style: TextStyle(fontFamily: AppFonts.openSans, color: AppColors.slateGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.slateGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(aiSetupControllerProvider.notifier).deleteProfile();
              if (mounted) {
                _syncControllersFromProfile();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile deleted'),
                      backgroundColor: AppColors.success),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }


  // ─── REUSABLE WIDGETS ──────────────────────────────────────────────────

  Widget _buildField(String label, TextEditingController ctrl, String hint,
      bool required) {
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

  Widget _buildCardField(String label, String value, ValueChanged<String> onChanged,
      {String? hint, int maxLines = 1, bool enabled = true}) {
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
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          const Text(' *',
              style: TextStyle(color: AppColors.error, fontSize: 13)),
      ],
    );
  }
}