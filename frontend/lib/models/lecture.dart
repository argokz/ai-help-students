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
