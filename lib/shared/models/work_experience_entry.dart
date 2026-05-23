// =============================================================================
// WORK EXPERIENCE ENTRY
//
// A single job record within a CV or AI profile. Embedded as a list inside
// the parent document — not stored as a separate Firestore collection.
// =============================================================================

class WorkExperienceEntry {
  final String jobTitle;
  final String company;
  final String startDate;       // stored as a display string, e.g. "Jan 2022"
  final String endDate;         // empty string when [isCurrentRole] is true
  final bool isCurrentRole;     // true → show "Present" instead of endDate
  final String description;     // bullet-point achievements / responsibilities

  const WorkExperienceEntry({
    this.jobTitle     = '',
    this.company      = '',
    this.startDate    = '',
    this.endDate      = '',
    this.isCurrentRole = false,
    this.description  = '',
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'jobTitle':      jobTitle,
    'company':       company,
    'startDate':     startDate,
    'endDate':       endDate,
    'isCurrentRole': isCurrentRole,
    'description':   description,
  };

  factory WorkExperienceEntry.fromJson(Map<String, dynamic> json) {
    return WorkExperienceEntry(
      jobTitle:      json['jobTitle']      ?? '',
      company:       json['company']       ?? '',
      startDate:     json['startDate']     ?? '',
      endDate:       json['endDate']       ?? '',
      isCurrentRole: json['isCurrentRole'] ?? false,
      description:   json['description']   ?? '',
    );
  }

  // ---------------------------------------------------------------------------
  // Immutable update
  // ---------------------------------------------------------------------------

  WorkExperienceEntry copyWith({
    String? jobTitle,
    String? company,
    String? startDate,
    String? endDate,
    bool?   isCurrentRole,
    String? description,
  }) {
    return WorkExperienceEntry(
      jobTitle:      jobTitle      ?? this.jobTitle,
      company:       company       ?? this.company,
      startDate:     startDate     ?? this.startDate,
      endDate:       endDate       ?? this.endDate,
      isCurrentRole: isCurrentRole ?? this.isCurrentRole,
      description:   description   ?? this.description,
    );
  }
}