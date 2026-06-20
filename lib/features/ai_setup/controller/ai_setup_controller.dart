// lib/features/ai_setup/controller/ai_setup_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../shared/models/ai_profile_model.dart';
import '../../../shared/services/firebase_service.dart';

class AiSetupState {
  final String? profileId;
  final bool isLoading;
  final bool isSaving;
  final String? error;
  final AiProfileModel profile;
  final int currentStep;

  AiSetupState({
    this.profileId,
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    AiProfileModel? profile,
    this.currentStep = 0,
  }) : profile = profile ?? const AiProfileModel();

  static const int totalSteps = 8;

  bool get isFirstStep => currentStep == 0;
  bool get isLastStep => currentStep == totalSteps - 1;
  double get progress => (currentStep + 1) / totalSteps;

  String get stepTitle {
    switch (currentStep) {
      case 0: return 'Personal Info';
      case 1: return 'Work Experience';
      case 2: return 'Education';
      case 3: return 'Skills & Languages';
      case 4: return 'Projects';
      case 5: return 'Awards & Volunteer';
      case 6: return 'Additional Info';
      case 7: return 'AI Preferences';
      default: return '';
    }
  }

  String get stepSubtitle {
    switch (currentStep) {
      case 0: return 'Basic contact & social links';
      case 1: return 'Add your work history';
      case 2: return 'Add your education';
      case 3: return 'Skills, languages & certifications';
      case 4: return 'Showcase your projects';
      case 5: return 'Awards, honors & volunteer work';
      case 6: return 'References, hobbies & custom sections';
      case 7: return 'How should AI write your content?';
      default: return '';
    }
  }

  AiSetupState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    String? profileId,
    AiProfileModel? profile,
    int? currentStep,
  }) {
    return AiSetupState(
      profileId: profileId ?? this.profileId,
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    state = state.copyWith(isSaving: true);

    try {
      final data = state.profile.toJson();
      data['updatedAt'] = FieldValue.serverTimestamp();

      // Save to new multi-profile collection
      final savedId = await FirebaseService.saveAiProfileMulti(
        uid, data, profileId: state.profileId,
      );

      // Also save to legacy path for backward compatibility
      await FirebaseService.saveAiProfile(uid, data);

      state = state.copyWith(isSaving: false, profileId: savedId);
      debugPrint('✅ AI profile saved: $savedId');
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: 'Save failed: $e');
      return false;
    }
  }

  Future<void> deleteProfile() async {
    if (_uid == null) return;
    try {
      await FirebaseService.saveAiProfile(_uid!, const AiProfileModel().toJson());
      state = state.copyWith(profile: const AiProfileModel());
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete profile: $e');
    }
  }

  void resetProfile() {
    state = state.copyWith(
      profile: const AiProfileModel(),
      profileId: null,
      isLoading: false,
    );
  }

  // ─── STEP 1: PERSONAL INFO ────────────────────────────────────────────

  void updatePersonalInfo({
    String? fullName,
    String? companyName,
    String? email,
    String? phone,
    String? location,
    String? linkedIn,
    String? website,
    String? profilePhotoUrl,
    String? dateOfBirth,
    String? nationality,
    String? gender,
  })
  {
    state = state.copyWith(
      profile: state.profile.copyWith(
        fullName: fullName,
        companyName: companyName,
        email: email,
        phone: phone,
        location: location,
        linkedIn: linkedIn,
        website: website,
        profilePhotoUrl: profilePhotoUrl,
        dateOfBirth: dateOfBirth,
        nationality: nationality,
        gender: gender,
      ),
    );
  }

  void updateSocialLinks(SocialLinks links) {
    state = state.copyWith(
      profile: state.profile.copyWith(socialLinks: links),
    );
  }

  // ─── STEP 2: WORK EXPERIENCE ──────────────────────────────────────────

  void addExperience() {
    final list = [...state.profile.experiences, const WorkExperienceEntry()];
    state = state.copyWith(profile: state.profile.copyWith(experiences: list));
  }

  void updateExperience(int index, WorkExperienceEntry entry) {
    final list = [...state.profile.experiences];
    if (index < list.length) {
      list[index] = entry;
      state = state.copyWith(profile: state.profile.copyWith(experiences: list));
    }
  }

  void removeExperience(int index) {
    final list = [...state.profile.experiences];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(experiences: list));
    }
  }

  // ─── STEP 3: EDUCATION ────────────────────────────────────────────────

  void addEducation() {
    final list = [...state.profile.education, const EducationEntry()];
    state = state.copyWith(profile: state.profile.copyWith(education: list));
  }

  void updateEducation(int index, EducationEntry entry) {
    final list = [...state.profile.education];
    if (index < list.length) {
      list[index] = entry;
      state = state.copyWith(profile: state.profile.copyWith(education: list));
    }
  }

  void removeEducation(int index) {
    final list = [...state.profile.education];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(education: list));
    }
  }

  // ─── STEP 4: SKILLS, LANGUAGES, CERTIFICATIONS ───────────────────────

  void addSkill(String skill) {
    if (skill.trim().isEmpty) return;
    final list = [...state.profile.skills];
    if (!list.contains(skill.trim())) {
      list.add(skill.trim());
      state = state.copyWith(profile: state.profile.copyWith(skills: list));
    }
  }

  void removeSkill(String skill) {
    final list = [...state.profile.skills]..remove(skill);
    state = state.copyWith(profile: state.profile.copyWith(skills: list));
  }

  void addLanguage(String language, String proficiency) {
    if (language.trim().isEmpty) return;
    final list = [...state.profile.languages,
      LanguageEntry(language: language.trim(), proficiency: proficiency)];
    state = state.copyWith(profile: state.profile.copyWith(languages: list));
  }

  void removeLanguage(int index) {
    final list = [...state.profile.languages];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(languages: list));
    }
  }

  void addCertification() {
    final list = [...state.profile.certifications, const CertificationEntry()];
    state = state.copyWith(profile: state.profile.copyWith(certifications: list));
  }

  void updateCertification(int index, CertificationEntry cert) {
    final list = [...state.profile.certifications];
    if (index < list.length) {
      list[index] = cert;
      state = state.copyWith(profile: state.profile.copyWith(certifications: list));
    }
  }

  void removeCertification(int index) {
    final list = [...state.profile.certifications];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(certifications: list));
    }
  }

  // ─── STEP 5: PROJECTS ────────────────────────────────────────────────

  void addProject() {
    final list = [...state.profile.projects, const ProjectEntry()];
    state = state.copyWith(profile: state.profile.copyWith(projects: list));
  }

  void updateProject(int index, ProjectEntry entry) {
    final list = [...state.profile.projects];
    if (index < list.length) {
      list[index] = entry;
      state = state.copyWith(profile: state.profile.copyWith(projects: list));
    }
  }

  void removeProject(int index) {
    final list = [...state.profile.projects];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(projects: list));
    }
  }

  // ─── STEP 6: AWARDS ──────────────────────────────────────────────────

  void addAward() {
    final list = [...state.profile.awards, const AwardEntry()];
    state = state.copyWith(profile: state.profile.copyWith(awards: list));
  }

  void updateAward(int index, AwardEntry entry) {
    final list = [...state.profile.awards];
    if (index < list.length) {
      list[index] = entry;
      state = state.copyWith(profile: state.profile.copyWith(awards: list));
    }
  }

  void removeAward(int index) {
    final list = [...state.profile.awards];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(awards: list));
    }
  }

  // ─── STEP 6: VOLUNTEER ───────────────────────────────────────────────

  void addVolunteer() {
    final list = [...state.profile.volunteerExperience, const VolunteerEntry()];
    state = state.copyWith(profile: state.profile.copyWith(volunteerExperience: list));
  }

  void updateVolunteer(int index, VolunteerEntry entry) {
    final list = [...state.profile.volunteerExperience];
    if (index < list.length) {
      list[index] = entry;
      state = state.copyWith(profile: state.profile.copyWith(volunteerExperience: list));
    }
  }

  void removeVolunteer(int index) {
    final list = [...state.profile.volunteerExperience];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(volunteerExperience: list));
    }
  }

  // ─── STEP 7: REFERENCES ──────────────────────────────────────────────

  void addReference() {
    final list = [...state.profile.references, const ReferenceEntry()];
    state = state.copyWith(profile: state.profile.copyWith(references: list));
  }

  void updateReference(int index, ReferenceEntry entry) {
    final list = [...state.profile.references];
    if (index < list.length) {
      list[index] = entry;
      state = state.copyWith(profile: state.profile.copyWith(references: list));
    }
  }

  void removeReference(int index) {
    final list = [...state.profile.references];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(references: list));
    }
  }

  // ─── STEP 7: HOBBIES ─────────────────────────────────────────────────

  void addHobby(String hobby) {
    if (hobby.trim().isEmpty) return;
    final list = [...state.profile.hobbies];
    if (!list.contains(hobby.trim())) {
      list.add(hobby.trim());
      state = state.copyWith(profile: state.profile.copyWith(hobbies: list));
    }
  }

  void removeHobby(String hobby) {
    final list = [...state.profile.hobbies]..remove(hobby);
    state = state.copyWith(profile: state.profile.copyWith(hobbies: list));
  }

  // ─── STEP 7: CUSTOM SECTIONS ─────────────────────────────────────────

  void addCustomSection() {
    final list = [...state.profile.customSections, const CustomSection()];
    state = state.copyWith(profile: state.profile.copyWith(customSections: list));
  }

  void updateCustomSection(int index, CustomSection section) {
    final list = [...state.profile.customSections];
    if (index < list.length) {
      list[index] = section;
      state = state.copyWith(profile: state.profile.copyWith(customSections: list));
    }
  }

  void removeCustomSection(int index) {
    final list = [...state.profile.customSections];
    if (index < list.length) {
      list.removeAt(index);
      state = state.copyWith(profile: state.profile.copyWith(customSections: list));
    }
  }

  // ─── STEP 8: AI PREFERENCES ──────────────────────────────────────────

  void updatePreferences({
    String? experienceLevel,
    String? tone,
    String? industry,
    String? jobTitle,
  })
  {
    state = state.copyWith(
      profile: state.profile.copyWith(
        experienceLevel: experienceLevel,
        tone: tone,
        industry: industry,
        jobTitle: jobTitle,
      ),
    );
  }

  /// Load a specific profile by ID for editing.
  Future<void> loadProfileById(String profileId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    state = state.copyWith(isLoading: true);

    try {
      final doc = await FirebaseService.getAiProfileById(uid, profileId);
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        state = state.copyWith(
          profile: AiProfileModel.fromJson(data),
          profileId: profileId,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load profile');
    }
  }
}

final aiSetupControllerProvider =
StateNotifierProvider<AiSetupController, AiSetupState>(
      (ref) => AiSetupController(),
);