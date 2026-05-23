// lib/shared/services/ai_prompts.dart
//
// Prompt engineering for CV section generation.
// Each section gets a specialized prompt that produces clean,
// professional text ready to insert into a QuillController.
//
// RULES FOR PROMPTS:
// - Output PLAIN TEXT only — no markdown, no bullet symbols, no headers
// - Use \n for line breaks between items
// - Keep output concise — CV space is limited (small text boxes)
// - Match the user's tone preference
// - Never fabricate specific companies/dates — use the user's real data
//
// Prompt cv_templates per CV section — system prompt builder, section matcher
// (summary, experience, skills, etc.), maps section titles to specialized prompts.


class AiPrompts {
  AiPrompts._();

  // ─── SYSTEM PROMPT (same for all sections) ─────────────────────────

  static String system({
    required String tone,
    required String experienceLevel,
  }) {
    return '''You are a professional CV writer. You write in a $tone tone for a $experienceLevel-level professional.

RULES:
- Output PLAIN TEXT only. No markdown, no headers, no bullet symbols (•, -, *).
- Use line breaks between separate items.
- Be concise — this text goes into a small CV text box.
- Write in third person or implied first person (no "I" unless tone is creative).
- Never invent company names, dates, or degrees — only use what's provided.
- If the user hasn't provided specific details, write realistic placeholder content that they can customize.
- Keep each section under 150 words unless the section type requires more.''';
  }

  // ─── PER-SECTION PROMPTS ───────────────────────────────────────────

  static String summary({
    required String jobTitle,
    required String experienceLevel,
    required List<String> skills,
    String? industry,
  }) {
    final skillsStr = skills.isNotEmpty ? skills.join(', ') : 'not specified';
    return '''Write a professional summary for a CV.

Job title: $jobTitle
Experience level: $experienceLevel
Key skills: $skillsStr
${industry != null && industry.isNotEmpty ? 'Industry: $industry' : ''}

Write 2-3 sentences summarizing their professional profile. This goes at the top of the CV under their name.''';
  }

  static String experience({
    required String jobTitle,
    required String experienceLevel,
    required List<String> skills,
    String? industry,
    List<Map<String, dynamic>>? existingExperience,
  }) {
    final skillsStr = skills.isNotEmpty ? skills.join(', ') : 'not specified';

    if (existingExperience != null && existingExperience.isNotEmpty) {
      final entries = existingExperience
          .map((e) {
            return '${e['jobTitle'] ?? 'Role'} at ${e['company'] ?? 'Company'} (${e['startDate'] ?? ''} - ${e['endDate'] ?? 'Present'})';
          })
          .join('\n');

      return '''Write work experience descriptions for a CV.

Their roles:
$entries

Skills to highlight: $skillsStr

For each role, write 2-3 achievement-focused lines. Start each achievement on a new line. Use action verbs (Led, Developed, Increased, Managed). Include quantified results where plausible.

Format:
Role Title
Company Name | Start - End
Achievement line 1
Achievement line 2
Achievement line 3

(separate each role with a blank line)''';
    }

    return '''Write sample work experience for a CV.

Target job title: $jobTitle
Experience level: $experienceLevel
Skills: $skillsStr
${industry != null && industry.isNotEmpty ? 'Industry: $industry' : ''}

Create 2 realistic sample roles with 2-3 achievement lines each. The user will customize the details later.

Format:
Role Title
Company Name | Start - End
Achievement line 1
Achievement line 2

(separate each role with a blank line)''';
  }

  static String education({
    required String experienceLevel,
    List<Map<String, dynamic>>? existingEducation,
  }) {
    if (existingEducation != null && existingEducation.isNotEmpty) {
      final entries = existingEducation
          .map((e) {
            return '${e['degree'] ?? 'Degree'} - ${e['school'] ?? 'School'} (${e['startDate'] ?? ''} - ${e['endDate'] ?? ''})';
          })
          .join('\n');

      return '''Format these education entries for a CV:

$entries

Format each entry as:
Degree Name
School Name | Start - End
(optional: field of study, honors, GPA if notable)

Keep it clean and concise.''';
    }

    return '''Write sample education entries for a CV.

Experience level: $experienceLevel

Create 1-2 realistic education entries appropriate for this level.

Format:
Degree Name
School Name | Start - End''';
  }

  static String skills({
    required List<String> skills,
    required String jobTitle,
    String? industry,
  }) {
    final existing = skills.isNotEmpty ? skills.join(', ') : 'none provided';

    return '''Write a skills section for a CV.

Job title: $jobTitle
${industry != null && industry.isNotEmpty ? 'Industry: $industry' : ''}
Existing skills: $existing

List 8-12 relevant skills, separated by line breaks. Mix technical and soft skills appropriate for this role. Put the most important skills first.

Output just the skill names, one per line. No categories, no headers, no bullet points.''';
  }

  static String certifications({
    required String jobTitle,
    required List<String> existingCerts,
    String? industry,
  }) {
    final existing = existingCerts.isNotEmpty
        ? 'They already have: ${existingCerts.join(', ')}'
        : 'No existing certifications provided.';

    return '''Suggest relevant certifications for a CV.

Job title: $jobTitle
${industry != null && industry.isNotEmpty ? 'Industry: $industry' : ''}
$existing

List 3-5 relevant certifications, one per line. Include the full certification name. If they have existing certs, list those first then suggest additional ones.

Output just the certification names, one per line.''';
  }

  static String languages({
    required List<Map<String, dynamic>>? existingLanguages,
  }) {
    if (existingLanguages != null && existingLanguages.isNotEmpty) {
      final entries = existingLanguages
          .map((e) {
            return '${e['language'] ?? 'Language'} - ${e['proficiency'] ?? 'Intermediate'}';
          })
          .join('\n');

      return '''Format these language entries for a CV:

$entries

Format as:
Language Name — Proficiency Level

One per line.''';
    }

    return '''Write sample language entries for a CV.

Include 2-3 languages with proficiency levels.

Format:
Language Name — Proficiency Level (Native/Fluent/Intermediate/Basic)

One per line.''';
  }

  static String contactInfo({
    required String fullName,
    String? email,
    String? phone,
    String? location,
    String? linkedIn,
    String? website,
  }) {
    return '''Format this contact information for a CV header:

Name: $fullName
${email != null && email.isNotEmpty ? 'Email: $email' : ''}
${phone != null && phone.isNotEmpty ? 'Phone: $phone' : ''}
${location != null && location.isNotEmpty ? 'Location: $location' : ''}
${linkedIn != null && linkedIn.isNotEmpty ? 'LinkedIn: $linkedIn' : ''}
${website != null && website.isNotEmpty ? 'Website: $website' : ''}

Output each piece of info on its own line. Only include fields that have values. No labels — just the values.''';
  }

  /// Generic section — when the section title doesn't match a known type
  static String generic({
    required String sectionTitle,
    required String jobTitle,
    required String experienceLevel,
    required List<String> skills,
  }) {
    final skillsStr = skills.isNotEmpty ? skills.join(', ') : 'not specified';
    return '''Write content for the "$sectionTitle" section of a CV.

Job title: $jobTitle
Experience level: $experienceLevel
Skills: $skillsStr

Write appropriate content for this section. Keep it concise and professional. Output plain text only with line breaks between items.''';
  }

  // ─── SECTION MATCHER ───────────────────────────────────────────────
  //
  // Maps a canvas text section title to the appropriate prompt builder.
  // The title comes from the CanvasItem.title field (layer name).

  static String matchSection({
    required String sectionTitle,
    required String jobTitle,
    required String experienceLevel,
    required String tone,
    required List<String> skills,
    String? industry,
    List<Map<String, dynamic>>? experiences,
    List<Map<String, dynamic>>? education,
    List<String>? certifications,
    List<Map<String, dynamic>>? languages,
    String? fullName,
    String? email,
    String? phone,
    String? location,
    String? linkedIn,
    String? website,
  }) {
    final lower = sectionTitle.toLowerCase().trim();

    // Summary / Profile / About / Objective
    if (lower.contains('summary') ||
        lower.contains('profile') ||
        lower.contains('about') ||
        lower.contains('objective')) {
      return summary(
        jobTitle: jobTitle,
        experienceLevel: experienceLevel,
        skills: skills,
        industry: industry,
      );
    }

    // Experience / Work / Employment
    if (lower.contains('experience') ||
        lower.contains('work') ||
        lower.contains('employment') ||
        lower.contains('career')) {
      return experience(
        jobTitle: jobTitle,
        experienceLevel: experienceLevel,
        skills: skills,
        industry: industry,
        existingExperience: experiences,
      );
    }

    // Education / Academic / Degree
    if (lower.contains('education') ||
        lower.contains('academic') ||
        lower.contains('degree') ||
        lower.contains('university') ||
        lower.contains('school')) {
      return AiPrompts.education(
        experienceLevel: experienceLevel,
        existingEducation: education,
      );
    }

    // Skills / Expertise / Competencies
    if (lower.contains('skill') ||
        lower.contains('expertise') ||
        lower.contains('competenc') ||
        lower.contains('technical')) {
      return AiPrompts.skills(
        skills: skills,
        jobTitle: jobTitle,
        industry: industry,
      );
    }

    // Certifications / Licenses
    if (lower.contains('certif') || lower.contains('license')) {
      return AiPrompts.certifications(
        jobTitle: jobTitle,
        existingCerts: certifications ?? [],
        industry: industry,
      );
    }

    // Languages
    if (lower.contains('language')) {
      return AiPrompts.languages(existingLanguages: languages);
    }

    // Contact / Header / Name
    if (lower.contains('contact') ||
        lower.contains('header') ||
        lower.contains('name') ||
        lower.contains('info')) {
      return contactInfo(
        fullName: fullName ?? '',
        email: email,
        phone: phone,
        location: location,
        linkedIn: linkedIn,
        website: website,
      );
    }

    // Fallback — generic
    return generic(
      sectionTitle: sectionTitle,
      jobTitle: jobTitle,
      experienceLevel: experienceLevel,
      skills: skills,
    );
  }
}
