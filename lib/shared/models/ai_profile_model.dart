// lib/shared/models/ai_profile_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'certification_entry.dart';
import 'education_entry.dart';
import 'language_entry.dart';
import 'work_experience_entry.dart';

class AiProfileModel {
  final String fullName;
  final String email;
  final String phone;
  final String location;
  final String? linkedIn;
  final String? website;

  final List<WorkExperienceEntry> experiences;
  final List<EducationEntry> education;
  final List<String> skills;
  final List<LanguageEntry> languages;
  final List<CertificationEntry> certifications;  // ← CHANGED from List<String>

  final String experienceLevel;
  final String tone;
  final String industry;
  final String? jobTitle;
  final DateTime? updatedAt;

  const AiProfileModel({
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.location = '',
    this.linkedIn,
    this.website,
    this.experiences = const [],
    this.education = const [],
    this.skills = const [],
    this.languages = const [],
    this.certifications = const [],
    this.experienceLevel = 'mid',
    this.tone = 'professional',
    this.industry = '',
    this.jobTitle,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'location': location,
    'linkedIn': linkedIn,
    'website': website,
    'experiences': experiences.map((e) => e.toJson()).toList(),
    'education': education.map((e) => e.toJson()).toList(),
    'skills': skills,
    'languages': languages.map((e) => e.toJson()).toList(),
    'certifications': certifications.map((e) => e.toJson()).toList(),
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
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      location: json['location'] ?? '',
      linkedIn: json['linkedIn'],
      website: json['website'],
      experiences: (json['experiences'] as List<dynamic>?)
          ?.map((e) => WorkExperienceEntry.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      education: (json['education'] as List<dynamic>?)
          ?.map((e) => EducationEntry.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      skills: List<String>.from(json['skills'] ?? []),
      languages: (json['languages'] as List<dynamic>?)
          ?.map((e) => LanguageEntry.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      certifications: certs,
      experienceLevel: json['experienceLevel'] ?? 'mid',
      tone: json['tone'] ?? 'professional',
      industry: json['industry'] ?? '',
      jobTitle: json['jobTitle'],
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  AiProfileModel copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? location,
    String? linkedIn,
    String? website,
    List<WorkExperienceEntry>? experiences,
    List<EducationEntry>? education,
    List<String>? skills,
    List<LanguageEntry>? languages,
    List<CertificationEntry>? certifications,
    String? experienceLevel,
    String? tone,
    String? industry,
    String? jobTitle,
  }) {
    return AiProfileModel(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      linkedIn: linkedIn ?? this.linkedIn,
      website: website ?? this.website,
      experiences: experiences ?? this.experiences,
      education: education ?? this.education,
      skills: skills ?? this.skills,
      languages: languages ?? this.languages,
      certifications: certifications ?? this.certifications,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      tone: tone ?? this.tone,
      industry: industry ?? this.industry,
      jobTitle: jobTitle ?? this.jobTitle,
      updatedAt: DateTime.now(),
    );
  }
}