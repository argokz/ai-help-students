class NoteAttachment {
  final String id;
  final String noteId;
  final String filePath; // URL or path
  final String fileType; // 'image', 'document'
  final String filename;
  final DateTime createdAt;

  NoteAttachment({
    required this.id,
    required this.noteId,
    required this.filePath,
    required this.fileType,
    required this.filename,
    required this.createdAt,
  });

  factory NoteAttachment.fromJson(Map<String, dynamic> json) {
    return NoteAttachment(
      id: json['id'],
      noteId: json['note_id'] ?? '', // API might not return it in nested list, but let's assume standard
      filePath: json['file_path'] ?? '', // This might need to be resolved to a full URL if relative
      fileType: json['file_type'] ?? 'document',
      filename: json['filename'] ?? 'unnamed',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class Note {
  final String id;
  final String? title;
  final String? content;
  final String? lectureId;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // Audio
  final bool hasAudio;
  final double? duration;
  final String status; // 'simple', 'processing', 'ready', 'error'
  final String? transcription;
  
  final List<NoteAttachment> attachments;

  Note({
    required this.id,
    this.title,
    this.content,
    this.lectureId,
    required this.createdAt,
    required this.updatedAt,
    this.hasAudio = false,
    this.duration,
    this.status = 'simple',
    this.transcription,
    this.attachments = const [],
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      lectureId: json['lecture_id'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      hasAudio: json['has_audio'] ?? false,
      duration: (json['duration'] as num?)?.toDouble(),
      status: json['status'] ?? 'simple',
      transcription: json['transcription'],
      attachments: (json['attachments'] as List?)
          ?.map((e) => NoteAttachment.fromJson(e))
          .toList() ?? [],
    );
  }
  
  String get titleDisplay => (title != null && title!.isNotEmpty) ? title! : 'Без названия';
  String get contentDisplay => (content != null && content!.isNotEmpty) ? content! : '';
}
