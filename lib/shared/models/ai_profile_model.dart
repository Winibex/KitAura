// lib/shared/models/ai_profile_model.dart
//
// Master profile used by AI to auto-fill CV/CL/proposal sections.
// Stored at users/{uid}/data/aiProfile in Firestore.
//
// CHANGES FROM PREVIOUS VERSION:
//   Added: profilePhotoUrl, dateOfBirth, nationality, gender
//   Added: socialLinks (GitHub, Twitter, Behance, Dribbble, etc.)
//   Added: projects (name, description, url, techStack, startDate, endDate)
//   Added: awards (title, issuer, date, description)
//   Added: volunteerExperience (role, organization, startDate, endDate, description)
//   Added: references (name, relationship, company, email, phone)
//   Added: hobbies (list of strings)
//   Added: customSections (title, content pairs)
//   All new fields are backwards compatible (default to null/empty)

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── SUB-MODELS ──────────────────────────────────────────────────────────

class WorkExperienceEntry {
  final String jobTitle;
  final String company;
  final String startDate;
  final String endDate;
  final bool isCurrentRole;
  final String description;

  const WorkExperienceEntry({
    this.jobTitle = '',
    this.company = '',
    this.startDate = '',
    this.endDate = '',
    this.isCurrentRole = false,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
    'jobTitle': jobTitle,
    'company': company,
    'startDate': startDate,
    'endDate': endDate,
    'isCurrentRole': isCurrentRole,
    'description': description,
  };

  factory WorkExperienceEntry.fromJson(Map<String, dynamic> json) =>
      WorkExperienceEntry(
        jobTitle: json['jobTitle'] ?? '',
        company: json['company'] ?? '',
        startDate: json['startDate'] ?? '',
        endDate: json['endDate'] ?? '',
        isCurrentRole: json['isCurrentRole'] ?? false,
        description: json['description'] ?? '',
      );

  WorkExperienceEntry copyWith({
    String? jobTitle,
    String? company,
    String? startDate,
    String? endDate,
    bool? isCurrentRole,
    String? description,
  }) => WorkExperienceEntry(
    jobTitle: jobTitle ?? this.jobTitle,
    company: company ?? this.company,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    isCurrentRole: isCurrentRole ?? this.isCurrentRole,
    description: description ?? this.description,
  );
}

class EducationEntry {
  final String degree;
  final String school;
  final String fieldOfStudy;
  final String startDate;
  final String endDate;
  final String? gradeType; // gpa | cgpa | percentage | marks | grade
  final String? gradeValue;

  const EducationEntry({
    this.degree = '',
    this.school = '',
    this.fieldOfStudy = '',
    this.startDate = '',
    this.endDate = '',
    this.gradeType,
    this.gradeValue,
  });

  Map<String, dynamic> toJson() => {
    'degree': degree,
    'school': school,
    'fieldOfStudy': fieldOfStudy,
    'startDate': startDate,
    'endDate': endDate,
    'gradeType': gradeType,
    'gradeValue': gradeValue,
  };

  factory EducationEntry.fromJson(Map<String, dynamic> json) {
    // Backwards compat: old 'gpa' field → gradeType: 'gpa'
    String? gt = json['gradeType'];
    String? gv = json['gradeValue'];
    if (gt == null && json['gpa'] != null) {
      gt = 'gpa';
      gv = json['gpa'].toString();
    }
    return EducationEntry(
      degree: json['degree'] ?? '',
      school: json['school'] ?? '',
      fieldOfStudy: json['fieldOfStudy'] ?? '',
      startDate: json['startDate'] ?? '',
      endDate: json['endDate'] ?? '',
      gradeType: gt,
      gradeValue: gv,
    );
  }

  EducationEntry copyWith({
    String? degree,
    String? school,
    String? fieldOfStudy,
    String? startDate,
    String? endDate,
    String? gradeType,
    String? gradeValue,
  }) => EducationEntry(
    degree: degree ?? this.degree,
    school: school ?? this.school,
    fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    gradeType: gradeType ?? this.gradeType,
    gradeValue: gradeValue ?? this.gradeValue,
  );
}

class LanguageEntry {
  final String language;
  final String proficiency; // native | fluent | intermediate | beginner

  const LanguageEntry({
    this.language = '',
    this.proficiency = 'intermediate',
  });

  Map<String, dynamic> toJson() => {
    'language': language,
    'proficiency': proficiency,
  };

  factory LanguageEntry.fromJson(Map<String, dynamic> json) => LanguageEntry(
    language: json['language'] ?? '',
    proficiency: json['proficiency'] ?? 'intermediate',
  );

  LanguageEntry copyWith({String? language, String? proficiency}) =>
      LanguageEntry(
        language: language ?? this.language,
        proficiency: proficiency ?? this.proficiency,
      );
}

class CertificationEntry {
  final String name;
  final String? institute;
  final String? issueDate;
  final String? expiryDate;
  final String? credentialId;
  final String? credentialUrl;
  final List<String> skills;

  const CertificationEntry({
    this.name = '',
    this.institute,
    this.issueDate,
    this.expiryDate,
    this.credentialId,
    this.credentialUrl,
    this.skills = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'institute': institute,
    'issueDate': issueDate,
    'expiryDate': expiryDate,
    'credentialId': credentialId,
    'credentialUrl': credentialUrl,
    'skills': skills,
  };

  factory CertificationEntry.fromJson(Map<String, dynamic> json) =>
      CertificationEntry(
        name: json['name'] ?? '',
        institute: json['institute'],
        issueDate: json['issueDate'],
        expiryDate: json['expiryDate'],
        credentialId: json['credentialId'],
        credentialUrl: json['credentialUrl'],
        skills: List<String>.from(json['skills'] ?? []),
      );

  /// Backwards compat: old format was just a string name
  factory CertificationEntry.fromString(String name) =>
      CertificationEntry(name: name);

  CertificationEntry copyWith({
    String? name,
    String? institute,
    String? issueDate,
    String? expiryDate,
    String? credentialId,
    String? credentialUrl,
    List<String>? skills,
  }) => CertificationEntry(
    name: name ?? this.name,
    institute: institute ?? this.institute,
    issueDate: issueDate ?? this.issueDate,
    expiryDate: expiryDate ?? this.expiryDate,
    credentialId: credentialId ?? this.credentialId,
    credentialUrl: credentialUrl ?? this.credentialUrl,
    skills: skills ?? this.skills,
  );
}

// ─── NEW SUB-MODELS ──────────────────────────────────────────────────────

class SocialLinks {
  final String? github;
  final String? twitter;
  final String? behance;
  final String? dribbble;
  final String? stackoverflow;
  final String? medium;
  final String? youtube;
  final String? portfolio;

  const SocialLinks({
    this.github,
    this.twitter,
    this.behance,
    this.dribbble,
    this.stackoverflow,
    this.medium,
    this.youtube,
    this.portfolio,
  });

  Map<String, dynamic> toJson() => {
    'github': github,
    'twitter': twitter,
    'behance': behance,
    'dribbble': dribbble,
    'stackoverflow': stackoverflow,
    'medium': medium,
    'youtube': youtube,
    'portfolio': portfolio,
  };

  factory SocialLinks.fromJson(Map<String, dynamic> json) => SocialLinks(
    github: json['github'],
    twitter: json['twitter'],
    behance: json['behance'],
    dribbble: json['dribbble'],
    stackoverflow: json['stackoverflow'],
    medium: json['medium'],
    youtube: json['youtube'],
    portfolio: json['portfolio'],
  );

  SocialLinks copyWith({
    String? github,
    String? twitter,
    String? behance,
    String? dribbble,
    String? stackoverflow,
    String? medium,
    String? youtube,
    String? portfolio,
  }) => SocialLinks(
    github: github ?? this.github,
    twitter: twitter ?? this.twitter,
    behance: behance ?? this.behance,
    dribbble: dribbble ?? this.dribbble,
    stackoverflow: stackoverflow ?? this.stackoverflow,
    medium: medium ?? this.medium,
    youtube: youtube ?? this.youtube,
    portfolio: portfolio ?? this.portfolio,
  );

  bool get isEmpty => github == null && twitter == null && behance == null &&
      dribbble == null && stackoverflow == null && medium == null &&
      youtube == null && portfolio == null;

  /// Returns non-null links as a flat list of "Platform: url" strings.
  List<String> toDisplayList() {
    final list = <String>[];
    if (github != null && github!.isNotEmpty) list.add('GitHub: $github');
    if (twitter != null && twitter!.isNotEmpty) list.add('Twitter: $twitter');
    if (behance != null && behance!.isNotEmpty) list.add('Behance: $behance');
    if (dribbble != null && dribbble!.isNotEmpty) list.add('Dribbble: $dribbble');
    if (stackoverflow != null && stackoverflow!.isNotEmpty) list.add('StackOverflow: $stackoverflow');
    if (medium != null && medium!.isNotEmpty) list.add('Medium: $medium');
    if (youtube != null && youtube!.isNotEmpty) list.add('YouTube: $youtube');
    if (portfolio != null && portfolio!.isNotEmpty) list.add('Portfolio: $portfolio');
    return list;
  }
}

class ProjectEntry {
  final String name;
  final String description;
  final String? url;
  final List<String> techStack;
  final String startDate;
  final String endDate;

  const ProjectEntry({
    this.name = '',
    this.description = '',
    this.url,
    this.techStack = const [],
    this.startDate = '',
    this.endDate = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'url': url,
    'techStack': techStack,
    'startDate': startDate,
    'endDate': endDate,
  };

  factory ProjectEntry.fromJson(Map<String, dynamic> json) => ProjectEntry(
    name: json['name'] ?? '',
    description: json['description'] ?? '',
    url: json['url'],
    techStack: List<String>.from(json['techStack'] ?? []),
    startDate: json['startDate'] ?? '',
    endDate: json['endDate'] ?? '',
  );

  ProjectEntry copyWith({
    String? name,
    String? description,
    String? url,
    List<String>? techStack,
    String? startDate,
    String? endDate,
  }) => ProjectEntry(
    name: name ?? this.name,
    description: description ?? this.description,
    url: url ?? this.url,
    techStack: techStack ?? this.techStack,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
  );
}

class AwardEntry {
  final String title;
  final String? issuer;
  final String? date;
  final String? description;

  const AwardEntry({
    this.title = '',
    this.issuer,
    this.date,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'issuer': issuer,
    'date': date,
    'description': description,
  };

  factory AwardEntry.fromJson(Map<String, dynamic> json) => AwardEntry(
    title: json['title'] ?? '',
    issuer: json['issuer'],
    date: json['date'],
    description: json['description'],
  );

  AwardEntry copyWith({
    String? title,
    String? issuer,
    String? date,
    String? description,
  }) => AwardEntry(
    title: title ?? this.title,
    issuer: issuer ?? this.issuer,
    date: date ?? this.date,
    description: description ?? this.description,
  );
}

class VolunteerEntry {
  final String role;
  final String organization;
  final String startDate;
  final String endDate;
  final String description;

  const VolunteerEntry({
    this.role = '',
    this.organization = '',
    this.startDate = '',
    this.endDate = '',
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'organization': organization,
    'startDate': startDate,
    'endDate': endDate,
    'description': description,
  };

  factory VolunteerEntry.fromJson(Map<String, dynamic> json) => VolunteerEntry(
    role: json['role'] ?? '',
    organization: json['organization'] ?? '',
    startDate: json['startDate'] ?? '',
    endDate: json['endDate'] ?? '',
    description: json['description'] ?? '',
  );

  VolunteerEntry copyWith({
    String? role,
    String? organization,
    String? startDate,
    String? endDate,
    String? description,
  }) => VolunteerEntry(
    role: role ?? this.role,
    organization: organization ?? this.organization,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    description: description ?? this.description,
  );
}

class ReferenceEntry {
  final String name;
  final String? relationship;
  final String? company;
  final String? email;
  final String? phone;

  const ReferenceEntry({
    this.name = '',
    this.relationship,
    this.company,
    this.email,
    this.phone,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'relationship': relationship,
    'company': company,
    'email': email,
    'phone': phone,
  };

  factory ReferenceEntry.fromJson(Map<String, dynamic> json) => ReferenceEntry(
    name: json['name'] ?? '',
    relationship: json['relationship'],
    company: json['company'],
    email: json['email'],
    phone: json['phone'],
  );

  ReferenceEntry copyWith({
    String? name,
    String? relationship,
    String? company,
    String? email,
    String? phone,
  }) => ReferenceEntry(
    name: name ?? this.name,
    relationship: relationship ?? this.relationship,
    company: company ?? this.company,
    email: email ?? this.email,
    phone: phone ?? this.phone,
  );
}

class CustomSection {
  final String title;
  final String content;

  const CustomSection({
    this.title = '',
    this.content = '',
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
  };

  factory CustomSection.fromJson(Map<String, dynamic> json) => CustomSection(
    title: json['title'] ?? '',
    content: json['content'] ?? '',
  );

  CustomSection copyWith({String? title, String? content}) => CustomSection(
    title: title ?? this.title,
    content: content ?? this.content,
  );
}

// ─── MAIN AI PROFILE MODEL ──────────────────────────────────────────────

class AiProfileModel {
  // Personal Info
  final String? id;
  final String name;
  final bool isDefault;
  final String fullName;
  final String email;
  final String phone;
  final String location;
  final String? linkedIn;
  final String? website;
  final String? profilePhotoUrl;
  final String? dateOfBirth;
  final String? nationality;
  final String? gender;

  // Social Links
  final SocialLinks socialLinks;

  // Experience
  final List<WorkExperienceEntry> experiences;

  // Education
  final List<EducationEntry> education;

  // Skills
  final List<String> skills;

  // Languages
  final List<LanguageEntry> languages;

  // Certifications
  final List<CertificationEntry> certifications;

  // Projects
  final List<ProjectEntry> projects;

  // Awards
  final List<AwardEntry> awards;

  // Volunteer Experience
  final List<VolunteerEntry> volunteerExperience;

  // References
  final List<ReferenceEntry> references;

  // Hobbies / Interests
  final List<String> hobbies;

  // Custom Sections
  final List<CustomSection> customSections;

  // AI Preferences
  final String experienceLevel;
  final String tone;
  final String industry;
  final String? jobTitle;

  final DateTime? updatedAt;

  const AiProfileModel({
    this.id,
    this.name = 'Default Profile',
    this.isDefault = false,
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.location = '',
    this.linkedIn,
    this.website,
    this.profilePhotoUrl,
    this.dateOfBirth,
    this.nationality,
    this.gender,
    this.socialLinks = const SocialLinks(),
    this.experiences = const [],
    this.education = const [],
    this.skills = const [],
    this.languages = const [],
    this.certifications = const [],
    this.projects = const [],
    this.awards = const [],
    this.volunteerExperience = const [],
    this.references = const [],
    this.hobbies = const [],
    this.customSections = const [],
    this.experienceLevel = 'mid',
    this.tone = 'professional',
    this.industry = '',
    this.jobTitle,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'isDefault': isDefault,
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'location': location,
    'linkedIn': linkedIn,
    'website': website,
    'profilePhotoUrl': profilePhotoUrl,
    'dateOfBirth': dateOfBirth,
    'nationality': nationality,
    'gender': gender,
    'socialLinks': socialLinks.toJson(),
    'experiences': experiences.map((e) => e.toJson()).toList(),
    'education': education.map((e) => e.toJson()).toList(),
    'skills': skills,
    'languages': languages.map((e) => e.toJson()).toList(),
    'certifications': certifications.map((e) => e.toJson()).toList(),
    'projects': projects.map((e) => e.toJson()).toList(),
    'awards': awards.map((e) => e.toJson()).toList(),
    'volunteerExperience': volunteerExperience.map((e) => e.toJson()).toList(),
    'references': references.map((e) => e.toJson()).toList(),
    'hobbies': hobbies,
    'customSections': customSections.map((e) => e.toJson()).toList(),
    'experienceLevel': experienceLevel,
    'tone': tone,
    'industry': industry,
    'jobTitle': jobTitle,
    'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
  };

  factory AiProfileModel.fromJson(Map<String, dynamic> json) {
    // Handle certifications: could be List<String> (old) or List<Map> (new)
    final rawCerts = json['certifications'] as List<dynamic>? ?? [];
    final certs = rawCerts.map((e) {
      if (e is String) return CertificationEntry.fromString(e);
      if (e is Map<String, dynamic>) return CertificationEntry.fromJson(e);
      if (e is Map) return CertificationEntry.fromJson(Map<String, dynamic>.from(e));
      return CertificationEntry.fromString(e.toString());
    }).toList();

    return AiProfileModel(
      id: json['id'] as String?,
      name: json['name'] ?? 'Default Profile',
      isDefault: json['isDefault'] ?? true,
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      location: json['location'] ?? '',
      linkedIn: json['linkedIn'],
      website: json['website'],
      profilePhotoUrl: json['profilePhotoUrl'],
      dateOfBirth: json['dateOfBirth'],
      nationality: json['nationality'],
      gender: json['gender'],
      socialLinks: json['socialLinks'] != null
          ? SocialLinks.fromJson(Map<String, dynamic>.from(json['socialLinks'] as Map))
          : const SocialLinks(),
      experiences: (json['experiences'] as List<dynamic>?)
          ?.map((e) => WorkExperienceEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      education: (json['education'] as List<dynamic>?)
          ?.map((e) => EducationEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      skills: List<String>.from(json['skills'] ?? []),
      languages: (json['languages'] as List<dynamic>?)
          ?.map((e) => LanguageEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      certifications: certs,
      projects: (json['projects'] as List<dynamic>?)
          ?.map((e) => ProjectEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      awards: (json['awards'] as List<dynamic>?)
          ?.map((e) => AwardEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      volunteerExperience: (json['volunteerExperience'] as List<dynamic>?)
          ?.map((e) => VolunteerEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      references: (json['references'] as List<dynamic>?)
          ?.map((e) => ReferenceEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      hobbies: List<String>.from(json['hobbies'] ?? []),
      customSections: (json['customSections'] as List<dynamic>?)
          ?.map((e) => CustomSection.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      experienceLevel: json['experienceLevel'] ?? 'mid',
      tone: json['tone'] ?? 'professional',
      industry: json['industry'] ?? '',
      jobTitle: json['jobTitle'],
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  AiProfileModel copyWith({
    String? id,
    String? name,
    bool? isDefault,
    String? fullName,
    String? email,
    String? phone,
    String? location,
    String? linkedIn,
    String? website,
    String? profilePhotoUrl,
    String? dateOfBirth,
    String? nationality,
    String? gender,
    SocialLinks? socialLinks,
    List<WorkExperienceEntry>? experiences,
    List<EducationEntry>? education,
    List<String>? skills,
    List<LanguageEntry>? languages,
    List<CertificationEntry>? certifications,
    List<ProjectEntry>? projects,
    List<AwardEntry>? awards,
    List<VolunteerEntry>? volunteerExperience,
    List<ReferenceEntry>? references,
    List<String>? hobbies,
    List<CustomSection>? customSections,
    String? experienceLevel,
    String? tone,
    String? industry,
    String? jobTitle,
  }) {
    return AiProfileModel(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      linkedIn: linkedIn ?? this.linkedIn,
      website: website ?? this.website,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      nationality: nationality ?? this.nationality,
      gender: gender ?? this.gender,
      socialLinks: socialLinks ?? this.socialLinks,
      experiences: experiences ?? this.experiences,
      education: education ?? this.education,
      skills: skills ?? this.skills,
      languages: languages ?? this.languages,
      certifications: certifications ?? this.certifications,
      projects: projects ?? this.projects,
      awards: awards ?? this.awards,
      volunteerExperience: volunteerExperience ?? this.volunteerExperience,
      references: references ?? this.references,
      hobbies: hobbies ?? this.hobbies,
      customSections: customSections ?? this.customSections,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      tone: tone ?? this.tone,
      industry: industry ?? this.industry,
      jobTitle: jobTitle ?? this.jobTitle,
      updatedAt: DateTime.now(),
    );
  }
}