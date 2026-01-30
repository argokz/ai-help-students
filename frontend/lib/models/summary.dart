class KeyDefinition {
  final String term;
  final String definition;

  KeyDefinition({
    required this.term,
    required this.definition,
  });

  factory KeyDefinition.fromJson(Map<String, dynamic> json) {
    return KeyDefinition(
      term: json['term'] as String,
      definition: json['definition'] as String,
    );
  }
}

class Summary {
  final String lectureId;
  final List<String> mainTopics;
  final List<KeyDefinition> keyDefinitions;
  final List<String> importantFacts;
  final List<String> assignments;
  final String briefSummary;
  final String? language;

  Summary({
    required this.lectureId,
    required this.mainTopics,
    required this.keyDefinitions,
    required this.importantFacts,
    required this.assignments,
    required this.briefSummary,
    this.language,
  });

  factory Summary.fromJson(Map<String, dynamic> json) {
    return Summary(
      lectureId: json['lecture_id'] as String,
      mainTopics: (json['main_topics'] as List).cast<String>(),
      keyDefinitions: (json['key_definitions'] as List)
          .map((d) => KeyDefinition.fromJson(d as Map<String, dynamic>))
          .toList(),
      importantFacts: (json['important_facts'] as List).cast<String>(),
      assignments: (json['assignments'] as List).cast<String>(),
      briefSummary: json['brief_summary'] as String,
      language: json['language'] as String?,
    );
  }
}
