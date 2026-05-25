// lib/shared/models/education_entry.dart

class EducationEntry {
  final String degree;
  final String school;
  final String startDate;
  final String endDate;
  final String? fieldOfStudy;

  // Grade: flexible system — GPA, marks, percentage, CGPA, etc.
  final String? gradeType;    // 'gpa' | 'cgpa' | 'percentage' | 'marks' | 'grade' | null
  final String? gradeValue;   // e.g. "3.8/4.0", "919/1100", "85%", "A+"

  const EducationEntry({
    this.degree = '',
    this.school = '',
    this.startDate = '',
    this.endDate = '',
    this.fieldOfStudy,
    this.gradeType,
    this.gradeValue,
  });

  Map<String, dynamic> toJson() => {
    'degree': degree,
    'school': school,
    'startDate': startDate,
    'endDate': endDate,
    'fieldOfStudy': fieldOfStudy,
    'gradeType': gradeType,
    'gradeValue': gradeValue,
  };

  factory EducationEntry.fromJson(Map<String, dynamic> json) {
    // Backwards compatible: if old 'gpa' field exists, migrate it
    String? gradeType = json['gradeType'] as String?;
    String? gradeValue = json['gradeValue'] as String?;
    if (gradeType == null && json['gpa'] != null && (json['gpa'] as String).isNotEmpty) {
      gradeType = 'gpa';
      gradeValue = json['gpa'] as String;
    }

    return EducationEntry(
      degree: json['degree'] ?? '',
      school: json['school'] ?? '',
      startDate: json['startDate'] ?? '',
      endDate: json['endDate'] ?? '',
      fieldOfStudy: json['fieldOfStudy'],
      gradeType: gradeType,
      gradeValue: gradeValue,
    );
  }

  EducationEntry copyWith({
    String? degree,
    String? school,
    String? startDate,
    String? endDate,
    String? fieldOfStudy,
    String? gradeType,
    String? gradeValue,
  }) {
    return EducationEntry(
      degree: degree ?? this.degree,
      school: school ?? this.school,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
      gradeType: gradeType ?? this.gradeType,
      gradeValue: gradeValue ?? this.gradeValue,
    );
  }

  /// Human-readable label for the grade type
  static String gradeTypeLabel(String? type) {
    switch (type) {
      case 'gpa': return 'GPA';
      case 'cgpa': return 'CGPA';
      case 'percentage': return 'Percentage';
      case 'marks': return 'Marks';
      case 'grade': return 'Grade';
      default: return 'Grade Type';
    }
  }

  static const List<String> gradeTypes = ['gpa', 'cgpa', 'percentage', 'marks', 'grade'];
}