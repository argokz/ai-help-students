class TranscriptSegment {
  final double start;
  final double end;
  final String text;

  TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      text: json['text'] as String,
    );
  }

  String get timestampText {
    final minutes = (start / 60).floor();
    final seconds = (start % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class Transcript {
  final String lectureId;
  final List<TranscriptSegment> segments;
  final String fullText;
  final String? language;

  Transcript({
    required this.lectureId,
    required this.segments,
    required this.fullText,
    this.language,
  });

  factory Transcript.fromJson(Map<String, dynamic> json) {
    return Transcript(
      lectureId: json['lecture_id'] as String,
      segments: (json['segments'] as List)
          .map((s) => TranscriptSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
      fullText: json['full_text'] as String,
      language: json['language'] as String?,
    );
  }
}
