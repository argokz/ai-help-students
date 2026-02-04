class Lecture {
  final String id;
  final String title;
  final String filename;
  final double? duration;
  final String? language;
  final String status;
  final DateTime createdAt;
  final bool hasTranscript;
  final bool hasSummary;
  /// 0.0–1.0 при status == processing (прогресс от сервера).
  final double? processingProgress;
  final String? subject;
  final String? groupName;

  Lecture({
    required this.id,
    required this.title,
    required this.filename,
    this.duration,
    this.language,
    required this.status,
    required this.createdAt,
    required this.hasTranscript,
    required this.hasSummary,
    this.processingProgress,
    this.subject,
    this.groupName,
  });

  factory Lecture.fromJson(Map<String, dynamic> json) {
    return Lecture(
      id: json['id'] as String,
      title: json['title'] as String,
      filename: json['filename'] as String,
      duration: json['duration'] as double?,
      language: json['language'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      hasTranscript: json['has_transcript'] as bool? ?? false,
      hasSummary: json['has_summary'] as bool? ?? false,
      processingProgress: (json['processing_progress'] as num?)?.toDouble(),
      subject: json['subject'] as String?,
      groupName: json['group_name'] as String?,
    );
  }

  String get statusText {
    switch (status) {
      case 'pending':
        return 'Ожидание';
      case 'processing':
        return 'Обработка...';
      case 'completed':
        return 'Готово';
      case 'failed':
        return 'Ошибка';
      default:
        return status;
    }
  }

  String get durationText {
    if (duration == null) return '--:--';
    final minutes = (duration! / 60).floor();
    final seconds = (duration! % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  bool get isReady => status == 'completed';
  bool get isProcessing => status == 'processing' || status == 'pending';
}

/// Результат умного поиска по лекциям.
class LectureSearchResult {
  final String id;
  final String title;
  final String? subject;
  final String? groupName;
  final String? snippet;
  final String? matchIn;

  LectureSearchResult({
    required this.id,
    required this.title,
    this.subject,
    this.groupName,
    this.snippet,
    this.matchIn,
  });

  factory LectureSearchResult.fromJson(Map<String, dynamic> json) {
    return LectureSearchResult(
      id: json['id'] as String,
      title: json['title'] as String,
      subject: json['subject'] as String?,
      groupName: json['group_name'] as String?,
      snippet: json['snippet'] as String?,
      matchIn: json['match_in'] as String?,
    );
  }
}
