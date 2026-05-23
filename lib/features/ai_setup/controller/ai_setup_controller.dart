import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/models/education_entry.dart';
import '../../../shared/models/language_entry.dart';
import '../../../shared/models/work_experience_entry.dart';
import '../../../shared/services/firebase_service.dart';

class AiSetupState {
  final bool isLoading;
  final bool isSaving;
  final String? error;
  final AiProfileModel profile;
  final int currentStep; // 0-4

  AiSetupState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    AiProfileModel? profile,
    this.currentStep = 0,
  }) : profile = profile ?? AiProfileModel();

  static const int totalSteps = 5;

  bool get isFirstStep => currentStep == 0;
  bool get isLastStep => currentStep == totalSteps - 1;
  double get progress => (currentStep + 1) / totalSteps;

  String get stepTitle {
    switch (currentStep) {
      case 0: return 'Personal Info';
      case 1: return 'Work Experience';
      case 2: return 'Education';
      case 3: return 'Skills & Languages';
      case 4: return 'AI Preferences';
      default: return '';
    }
  }

  String get stepSubtitle {
    switch (currentStep) {
      case 0: return 'Basic contact information';
      case 1: return 'Add your work history';
      case 2: return 'Add your education';
      case 3: return 'Skills, languages & certifications';
      case 4: return 'How should AI write your content?';
      default: return '';
    }
  }

  AiSetupState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    AiProfileModel? profile,
    int? currentStep,
  }) {
    return AiSetupState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error,
      profile: profile ?? this.profile,
      currentStep: currentStep ?? this.currentStep,
    );
  }
}

class AiSetupController extends StateNotifier<AiSetupState> {
  AiSetupController() : super(AiSetupState());

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ─── NAVIGATION ───────────────────────────────────────────────────────

  void nextStep() {
    if (!state.isLastStep) {
      state = state.copyWith(currentStep: state.currentStep + 1, error: null);
    }
  }

  void previousStep() {
    if (!state.isFirstStep) {
      state = state.copyWith(currentStep: state.currentStep - 1, error: null);
    }
  }

  void goToStep(int step) {
    if (step >= 0 && step < AiSetupState.totalSteps) {
      state = state.copyWith(currentStep: step, error: null);
    }
  }

  // ─── LOAD / SAVE ──────────────────────────────────────────────────────

  Future<void> loadProfile() async {
    if (_uid == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final doc = await FirebaseService.getAiProfile(_uid!);
      if (doc.exists) {
        final profile =
        AiProfileModel.fromJson(doc.data() as Map<String, dynamic>);
        state = state.copyWith(isLoading: false, profile: profile);
      } else {
        // Pre-fill from Firebase Auth
        final user = FirebaseAuth.instance.currentUser;
        state = state.copyWith(
          isLoading: false,
          profile: AiProfileModel(
            fullName: user?.displayName ?? '',
            email: user?.email ?? '',
          ),
        );
      }
    } catch (e) {
      debugPrint('loadProfile error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> saveProfile() async {
    if (_uid == null) return false;
    state = state.copyWith(isSaving: true, error: null);
    try {
      await FirebaseService.saveAiProfile(_uid!, state.profile.toJson());
      state = state.copyWith(isSaving: false);
      return true;
    } catch (e) {
      debugPrint('saveProfile error: $e');
      state = state.copyWith(
        isSaving: false,
        error: 'Failed to save. Please try again.',
      );
      return false;
    }
  }

  // ─── STEP 1: PERSONAL INFO ────────────────────────────────────────────

  void updatePersonalInfo({
    String? fullName,
    String? email,
    String? phone,
    String? location,
    String? linkedIn,
    String? website,
  }) {
    state = state.copyWith(
      profile: state.profile.copyWith(
        fullName: fullName,
        email: email,
        phone: phone,
        location: location,
        linkedIn: linkedIn,
        website: website,
      ),
    );
  }

  // ─── STEP 2: WORK EXPERIENCE ──────────────────────────────────────────

  void addExperience() {
    final list = List<WorkExperienceEntry>.from(state.profile.experiences);
    list.add(WorkExperienceEntry());
    state = state.copyWith(
      profile: state.profile.copyWith(experiences: list),
    );
  }

  void updateExperience(int index, WorkExperienceEntry entry) {
    final list = List<WorkExperienceEntry>.from(state.profile.experiences);
    if (index < list.length) {
      list[index] = entry;
      state = state.copyWith(
        profile: state.profile.copyWith(experiences: list),
      );
    }
  }

  void removeExperience(int index) {
    final list = List<WorkExperienceEntry>.from(state.profile.experiences);
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(
        profile: state.profile.copyWith(experiences: list),
      );
    }
  }

  // ─── STEP 3: EDUCATION ────────────────────────────────────────────────

  void addEducation() {
    final list = List<EducationEntry>.from(state.profile.education);
    list.add(EducationEntry());
    state = state.copyWith(
      profile: state.profile.copyWith(education: list),
    );
  }

  void updateEducation(int index, EducationEntry entry) {
    final list = List<EducationEntry>.from(state.profile.education);
    if (index < list.length) {
      list[index] = entry;
      state = state.copyWith(
        profile: state.profile.copyWith(education: list),
      );
    }
  }

  void removeEducation(int index) {
    final list = List<EducationEntry>.from(state.profile.education);
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(
        profile: state.profile.copyWith(education: list),
      );
    }
  }

  // ─── STEP 4: SKILLS & LANGUAGES ───────────────────────────────────────

  void addSkill(String skill) {
    if (skill.trim().isEmpty) return;
    final list = List<String>.from(state.profile.skills);
    if (!list.contains(skill.trim())) {
      list.add(skill.trim());
      state = state.copyWith(
        profile: state.profile.copyWith(skills: list),
      );
    }
  }

  void removeSkill(String skill) {
    final list = List<String>.from(state.profile.skills);
    list.remove(skill);
    state = state.copyWith(
      profile: state.profile.copyWith(skills: list),
    );
  }

  void addLanguage(String language, String proficiency) {
    if (language.trim().isEmpty) return;
    final list = List<LanguageEntry>.from(state.profile.languages);
    list.add(LanguageEntry(
        language: language.trim(), proficiency: proficiency));
    state = state.copyWith(
      profile: state.profile.copyWith(languages: list),
    );
  }

  void removeLanguage(int index) {
    final list = List<LanguageEntry>.from(state.profile.languages);
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(
        profile: state.profile.copyWith(languages: list),
      );
    }
  }

  void addCertification(String cert) {
    if (cert.trim().isEmpty) return;
    final list = List<String>.from(state.profile.certifications);
    if (!list.contains(cert.trim())) {
      list.add(cert.trim());
      state = state.copyWith(
        profile: state.profile.copyWith(certifications: list),
      );
    }
  }

  void removeCertification(String cert) {
    final list = List<String>.from(state.profile.certifications);
    list.remove(cert);
    state = state.copyWith(
      profile: state.profile.copyWith(certifications: list),
    );
  }

  // ─── STEP 5: AI PREFERENCES ───────────────────────────────────────────

  void updatePreferences({
    String? experienceLevel,
    String? tone,
    String? industry,
    String? jobTitle,
  }) {
    state = state.copyWith(
      profile: state.profile.copyWith(
        experienceLevel: experienceLevel,
        tone: tone,
        industry: industry,
        jobTitle: jobTitle,
      ),
    );
  }
}

// Provider
final aiSetupControllerProvider =
StateNotifierProvider<AiSetupController, AiSetupState>(
      (ref) => AiSetupController(),
);