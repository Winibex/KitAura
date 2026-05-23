// =============================================================================
// AI PROFILE
// Firestore path: users/{uid}/data/aiProfile
//
// The master profile that the AI uses to auto-fill CV sections. Users build
// this once; the AI then tailors content for each individual CV. Storing it
// separately from the CV documents avoids duplication and lets the user keep
// a single source of truth for their background.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kitaura/shared/models/work_experience_entry.dart';

import 'education_entry.dart';
import 'language_entry.dart';

class AiProfileModel {
  // Contact information
  final String fullName;
  final String email;
  final String phone;
  final String location;
  final String? linkedIn;
  final String? website;

  // Career history (ordered, most recent first by convention)
  final List<WorkExperienceEntry> experiences;
  final List<EducationEntry> education;

  // Skills & extras
  final List<String> skills;
  final List<LanguageEntry> languages;
  final List<String> certifications;

  // AI generation preferences — influence tone and content targeting
  final String experienceLevel; // 'junior' | 'mid' | 'senior' | 'executive'
  final String tone;            // 'professional' | 'creative' | 'technical' etc.
  final String industry;
  final String? jobTitle;       // current or target job title

  final DateTime? updatedAt;

  const AiProfileModel({
    this.fullName        = '',
    this.email           = '',
    this.phone           = '',
    this.location        = '',
    this.linkedIn,
    this.website,
    this.experiences     = const [],
    this.education       = const [],
    this.skills          = const [],
    this.languages       = const [],
    this.certifications  = const [],
    this.experienceLevel = 'mid',
    this.tone            = 'professional',
    this.industry        = '',
    this.jobTitle,
    this.updatedAt,
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Nested lists (experiences, education, languages) are serialized by calling
  /// each entry's own [toJson] method, producing a list of maps.
  Map<String, dynamic> toJson() => {
    'fullName':        fullName,
    'email':           email,
    'phone':           phone,
    'location':        location,
    'linkedIn':        linkedIn,
    'website':         website,
    'experiences':     experiences.map((e) => e.toJson()).toList(),
    'education':       education.map((e) => e.toJson()).toList(),
    'skills':          skills,
    'languages':       languages.map((e) => e.toJson()).toList(),
    'certifications':  certifications,
    'experienceLevel': experienceLevel,
    'tone':            tone,
    'industry':        industry,
    'jobTitle':        jobTitle,
    'updatedAt':       Timestamp.fromDate(updatedAt ?? DateTime.now()),
  };

  factory AiProfileModel.fromJson(Map<String, dynamic> json) {
    return AiProfileModel(
      fullName:        json['fullName']        ?? '',
      email:           json['email']           ?? '',
      phone:           json['phone']           ?? '',
      location:        json['location']        ?? '',
      linkedIn:        json['linkedIn'],
      website:         json['website'],

      // Each nested list is cast to List<dynamic> then mapped through the
      // appropriate fromJson factory. Falls back to empty list if missing.
      experiences: (json['experiences'] as List<dynamic>?)
          ?.map((e) => WorkExperienceEntry.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      education: (json['education'] as List<dynamic>?)
          ?.map((e) => EducationEntry.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      skills:         List<String>.from(json['skills'] ?? []),
      languages: (json['languages'] as List<dynamic>?)
          ?.map((e) => LanguageEntry.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
      certifications:  List<String>.from(json['certifications'] ?? []),
      experienceLevel: json['experienceLevel'] ?? 'mid',
      tone:            json['tone']            ?? 'professional',
      industry:        json['industry']        ?? '',
      jobTitle:        json['jobTitle'],
      updatedAt:      (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // ---------------------------------------------------------------------------
  // Immutable update
  // ---------------------------------------------------------------------------

  /// [updatedAt] is always stamped to now so the profile's freshness is
  /// tracked without the caller needing to supply the timestamp.
  AiProfileModel copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? location,
    String? linkedIn,
    String? website,
    List<WorkExperienceEntry>? experiences,
    List<EducationEntry>?      education,
    List<String>?              skills,
    List<LanguageEntry>?       languages,
    List<String>?              certifications,
    String? experienceLevel,
    String? tone,
    String? industry,
    String? jobTitle,
  }) {
    return AiProfileModel(
      fullName:        fullName        ?? this.fullName,
      email:           email           ?? this.email,
      phone:           phone           ?? this.phone,
      location:        location        ?? this.location,
      linkedIn:        linkedIn        ?? this.linkedIn,
      website:         website         ?? this.website,
      experiences:     experiences     ?? this.experiences,
      education:       education       ?? this.education,
      skills:          skills          ?? this.skills,
      languages:       languages       ?? this.languages,
      certifications:  certifications  ?? this.certifications,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      tone:            tone            ?? this.tone,
      industry:        industry        ?? this.industry,
      jobTitle:        jobTitle        ?? this.jobTitle,
      updatedAt:       DateTime.now(),
    );
  }
}