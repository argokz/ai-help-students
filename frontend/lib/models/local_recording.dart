/// Локальная запись на устройстве (до или после загрузки на сервер).
class LocalRecording {
  final String path;
  final String title;
  final String? language;
  final int createdAtMillis;

  LocalRecording({
    required this.path,
    required this.title,
    this.language,
    required this.createdAtMillis,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'language': language,
        'createdAtMillis': createdAtMillis,
      };

  factory LocalRecording.fromJson(Map<String, dynamic> json) {
    return LocalRecording(
      path: json['path'] as String,
      title: json['title'] as String,
      language: json['language'] as String?,
      createdAtMillis: json['createdAtMillis'] as int,
    );
  }

  String get fileName {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }
}
