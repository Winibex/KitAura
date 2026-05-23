// =============================================================================
// EDUCATION ENTRY
//
// A single education record (degree / institution). Embedded as a list inside
// the parent document — not stored as a separate Firestore collection.
// =============================================================================

class EducationEntry {
  final String degree;
  final String school;
  final String startDate;
  final String endDate;
  final String? gpa;           // optional — many users prefer not to include it
  final String? fieldOfStudy;  // optional — may be implied by the degree name

  const EducationEntry({
    this.degree       = '',
    this.school       = '',
    this.startDate    = '',
    this.endDate      = '',
    this.gpa,
    this.fieldOfStudy,
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'degree':       degree,
    'school':       school,
    'startDate':    startDate,
    'endDate':      endDate,
    'gpa':          gpa,
    'fieldOfStudy': fieldOfStudy,
  };

  factory EducationEntry.fromJson(Map<String, dynamic> json) {
    return EducationEntry(
      degree:       json['degree']       ?? '',
      school:       json['school']       ?? '',
      startDate:    json['startDate']    ?? '',
      endDate:      json['endDate']      ?? '',
      gpa:          json['gpa'],
      fieldOfStudy: json['fieldOfStudy'],
    );
  }

  // ---------------------------------------------------------------------------
  // Immutable update
  // ---------------------------------------------------------------------------

  EducationEntry copyWith({
    String? degree,
    String? school,
    String? startDate,
    String? endDate,
    String? gpa,
    String? fieldOfStudy,
  }) {
    return EducationEntry(
      degree:       degree       ?? this.degree,
      school:       school       ?? this.school,
      startDate:    startDate    ?? this.startDate,
      endDate:      endDate      ?? this.endDate,
      gpa:          gpa          ?? this.gpa,
      fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
    );
  }
}