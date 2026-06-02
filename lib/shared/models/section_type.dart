// lib/shared/models/section_type.dart
//
// Identifies what KIND of CV section a text item represents.
// Used by AI autofill, AI Fill, and section detection.
//
// CHANGES: Added volunteer, references, hobbies, socialLinks

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
  volunteer,
  references,
  hobbies,
  socialLinks,
  custom;

  /// Human-readable label for the dropdown.
  String get label {
    switch (this) {
      case SectionType.name:
        return 'Full Name';
      case SectionType.jobTitle:
        return 'Job Title';
      case SectionType.contact:
        return 'Contact Info';
      case SectionType.summary:
        return 'Summary / Profile';
      case SectionType.experience:
        return 'Work Experience';
      case SectionType.education:
        return 'Education';
      case SectionType.skills:
        return 'Skills';
      case SectionType.projects:
        return 'Projects';
      case SectionType.certifications:
        return 'Certifications';
      case SectionType.awards:
        return 'Awards / Honors';
      case SectionType.languages:
        return 'Languages';
      case SectionType.interests:
        return 'Interests';
      case SectionType.volunteer:
        return 'Volunteer Experience';
      case SectionType.references:
        return 'References';
      case SectionType.hobbies:
        return 'Hobbies';
      case SectionType.socialLinks:
        return 'Social Links';
      case SectionType.custom:
        return 'Custom';
    }
  }

  /// Whether this section can be auto-filled from the AI profile.
  bool get isAutofillable {
    switch (this) {
      case SectionType.custom:
        return false;
      default:
        return true;
    }
  }

  /// Stable key for JSON serialization (uses the enum name).
  /// We use toString().split('.').last instead of .name because
  /// Dart's .name getter conflicts with SectionType.name enum value.
  String get key => toString().split('.').last;

  /// Parse from a stored key string.
  static SectionType fromKey(String key) {
    return SectionType.values.firstWhere(
      (t) => t.key == key,
      orElse: () => SectionType.custom,
    );
  }

  /// Auto-detect section type from a title string.
  static SectionType detectFromTitle(String title) {
    final t = title.toLowerCase().trim();

    if (t.contains('name') || t.contains('full name')) return SectionType.name;
    if (t.contains('job title') ||
        t.contains('role') ||
        t.contains('position') ||
        t.contains('designation')) {
      return SectionType.jobTitle;
    }
    if (t.contains('contact') ||
        t.contains('email') ||
        t.contains('phone') ||
        t.contains('address')) {
      return SectionType.contact;
    }
    if (t.contains('summary') ||
        t.contains('profile') ||
        t.contains('objective') ||
        t.contains('about')) {
      return SectionType.summary;
    }
    if (t.contains('experience') ||
        t.contains('work') ||
        t.contains('employment') ||
        t.contains('career')) {
      return SectionType.experience;
    }
    if (t.contains('education') ||
        t.contains('academic') ||
        t.contains('qualification') ||
        t.contains('degree')) {
      return SectionType.education;
    }
    if (t.contains('skill') ||
        t.contains('competenc') ||
        t.contains('technical') ||
        t.contains('expertise')) {
      return SectionType.skills;
    }
    if (t.contains('project')) return SectionType.projects;
    if (t.contains('certif') ||
        t.contains('license') ||
        t.contains('accreditation')) {
      return SectionType.certifications;
    }
    if (t.contains('award') ||
        t.contains('honor') ||
        t.contains('achievement') ||
        t.contains('recognition')) {
      return SectionType.awards;
    }
    if (t.contains('language')) return SectionType.languages;
    if (t.contains('interest') || t.contains('hobby') || t.contains('hobbies')) {
      return SectionType.hobbies;
    }
    if (t.contains('volunteer') ||
        t.contains('community') ||
        t.contains('non-profit')) {
      return SectionType.volunteer;
    }
    if (t.contains('reference')) return SectionType.references;
    if (t.contains('social') ||
        t.contains('github') ||
        t.contains('twitter') ||
        t.contains('portfolio')) {
      return SectionType.socialLinks;
    }

    return SectionType.custom;
  }
}
