// lib/shared/models/certification_entry.dart
//
// A structured certification record. Replaces the old List<String> certifications.

class CertificationEntry {
  final String name;
  final String? institute;       // issuing organization
  final String? issueDate;       // e.g. "Jan 2024"
  final String? expiryDate;      // null if no expiry
  final String? credentialId;    // certificate number / credential ID
  final String? credentialUrl;   // verification URL
  final List<String> skills;     // associated skills

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

  factory CertificationEntry.fromJson(Map<String, dynamic> json) {
    return CertificationEntry(
      name: json['name'] as String? ?? '',
      institute: json['institute'] as String?,
      issueDate: json['issueDate'] as String?,
      expiryDate: json['expiryDate'] as String?,
      credentialId: json['credentialId'] as String?,
      credentialUrl: json['credentialUrl'] as String?,
      skills: List<String>.from(json['skills'] ?? []),
    );
  }

  /// Backwards compatible: create from a plain string (old format)
  factory CertificationEntry.fromString(String name) {
    return CertificationEntry(name: name);
  }

  CertificationEntry copyWith({
    String? name,
    String? institute,
    String? issueDate,
    String? expiryDate,
    String? credentialId,
    String? credentialUrl,
    List<String>? skills,
  }) {
    return CertificationEntry(
      name: name ?? this.name,
      institute: institute ?? this.institute,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      credentialId: credentialId ?? this.credentialId,
      credentialUrl: credentialUrl ?? this.credentialUrl,
      skills: skills ?? this.skills,
    );
  }
}