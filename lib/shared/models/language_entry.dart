// =============================================================================
// LANGUAGE ENTRY
//
// A language the user speaks, along with their self-reported proficiency level.
// Typical proficiency values: 'beginner' | 'intermediate' | 'fluent' | 'native'
// =============================================================================

class LanguageEntry {
  final String language;
  final String proficiency; // defaults to 'intermediate' if not specified

  const LanguageEntry({
    this.language    = '',
    this.proficiency = 'intermediate',
  });

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'language':    language,
    'proficiency': proficiency,
  };

  factory LanguageEntry.fromJson(Map<String, dynamic> json) {
    return LanguageEntry(
      language:    json['language']    ?? '',
      proficiency: json['proficiency'] ?? 'intermediate',
    );
  }
}