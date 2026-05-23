// lib/shared/models/section_type.dart
//
// Identifies what KIND of CV section a text item represents, so the AI
// autofill knows which profile data to put where. Independent of
// CanvasItemType (which is always `textSection` for these).

enum SectionType {
  name,
  jobTitle,
  contact,
  summary,
  experience,
  education,
  skills,
  projects,
  certifications,
  awards,
  languages,
  interests,
  custom; // unknown / user-defined — AI leaves it alone

  /// Human-readable label for the dropdown.
  String get label {
    switch (this) {
      case SectionType.name:           return 'Full Name';
      case SectionType.jobTitle:       return 'Job Title';
      case SectionType.contact:        return 'Contact Info';
      case SectionType.summary:        return 'Summary / Profile';
      case SectionType.experience:     return 'Work Experience';
      case SectionType.education:      return 'Education';
      case SectionType.skills:         return 'Skills';
      case SectionType.projects:       return 'Projects';
      case SectionType.certifications: return 'Certifications';
      case SectionType.awards:         return 'Awards';
      case SectionType.languages:      return 'Languages';
      case SectionType.interests:      return 'Interests';
      case SectionType.custom:         return 'Custom / Other';
    }
  }

  /// Serialize to a stable string for JSON / Firestore.
  String get key => toString().split('.').last;

  /// Parse from a stored string.
  static SectionType fromKey(String? key) {
    if (key == null) return SectionType.custom;
    return SectionType.values.firstWhere(
          (t) => t.toString().split('.').last == key,
      orElse: () => SectionType.custom,
    );
  }

  /// Auto-detect the section type from a title string.
  /// Used when loading templates that don't have an explicit sectionType.
  static SectionType detectFromTitle(String title) {
    final t = title.toLowerCase().trim();

    // Order matters — check more specific terms first
    if (_matchesAny(t, ['full name', 'name'])) return SectionType.name;
    if (_matchesAny(t, ['job title', 'title', 'role', 'position', 'headline'])) {
      return SectionType.jobTitle;
    }
    if (_matchesAny(t, ['contact', 'details', 'info', 'phone', 'email'])) {
      return SectionType.contact;
    }
    if (_matchesAny(t, ['summary', 'profile', 'about', 'objective', 'overview', 'executive summary'])) {
      return SectionType.summary;
    }
    if (_matchesAny(t, ['experience', 'employment', 'work history', 'career', 'professional experience', 'leadership'])) {
      return SectionType.experience;
    }
    if (_matchesAny(t, ['education', 'academic', 'qualification', 'degree'])) {
      return SectionType.education;
    }
    if (_matchesAny(t, ['technical skills', 'soft skills', 'skills', 'expertise', 'competence', 'technologies'])) {
      return SectionType.skills;
    }
    if (_matchesAny(t, ['project'])) return SectionType.projects;
    if (_matchesAny(t, ['certification', 'cert', 'license', 'credential'])) {
      return SectionType.certifications;
    }
    if (_matchesAny(t, ['award', 'achievement', 'honor', 'honour', 'recognition'])) {
      return SectionType.awards;
    }
    if (_matchesAny(t, ['language'])) return SectionType.languages;
    if (_matchesAny(t, ['interest', 'hobby', 'hobbies', 'activities'])) {
      return SectionType.interests;
    }

    return SectionType.custom;
  }

  static bool _matchesAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// Whether the AI autofill can populate this section from profile data.
  bool get isAutofillable => this != SectionType.custom;
}