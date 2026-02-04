class SourceChunk {
  final String text;
  final double startTime;
  final double endTime;
  final double relevanceScore;

  SourceChunk({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.relevanceScore,
  });

  factory SourceChunk.fromJson(Map<String, dynamic> json) {
    return SourceChunk(
      text: json['text'] as String,
      startTime: (json['start_time'] as num).toDouble(),
      endTime: (json['end_time'] as num).toDouble(),
      relevanceScore: (json['relevance_score'] as num).toDouble(),
    );
  }

  String get timestampText {
    final minutes = (startTime / 60).floor();
    final seconds = (startTime % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final List<SourceChunk>? sources;
  final double? confidence;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.sources,
    this.confidence,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
    };
  }
}

class ChatResponse {
  final String answer;
  final List<SourceChunk> sources;
  final double? confidence;

  ChatResponse({
    required this.answer,
    required this.sources,
    this.confidence,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      answer: json['answer'] as String,
      sources: (json['sources'] as List)
          .map((s) => SourceChunk.fromJson(s as Map<String, dynamic>))
          .toList(),
      confidence: json['confidence'] as double?,
    );
  }
}

/// Источник в общем чате — лекция.
class GlobalChatSource {
  final String lectureId;
  final String lectureTitle;
  final String snippet;

  GlobalChatSource({
    required this.lectureId,
    required this.lectureTitle,
    required this.snippet,
  });

  factory GlobalChatSource.fromJson(Map<String, dynamic> json) {
    return GlobalChatSource(
      lectureId: json['lecture_id'] as String,
      lectureTitle: json['lecture_title'] as String,
      snippet: json['snippet'] as String,
    );
  }
}

/// Ответ общего чата по всем лекциям.
class GlobalChatResponse {
  final String answer;
  final List<GlobalChatSource> sources;

  GlobalChatResponse({
    required this.answer,
    required this.sources,
  });

  factory GlobalChatResponse.fromJson(Map<String, dynamic> json) {
    return GlobalChatResponse(
      answer: json['answer'] as String,
      sources: (json['sources'] as List)
          .map((s) => GlobalChatSource.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
