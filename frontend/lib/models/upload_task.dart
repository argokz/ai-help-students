/// Состояние одной задачи загрузки лекции.
enum UploadTaskStatus {
  uploading,
  processing,
  completed,
  failed,
}

/// Задача загрузки: файл → сервер → обработка на сервере.
class UploadTask {
  final String id;
  final String filePath;
  final String? title;
  final String? language;

  /// 0.0..1.0 — прогресс отправки файла на сервер.
  double uploadProgress;
  UploadTaskStatus status;
  /// После успешной отправки — id лекции на сервере.
  String? lectureId;
  /// Сообщение об ошибке (при status == failed).
  String? errorMessage;

  UploadTask({
    required this.id,
    required this.filePath,
    this.title,
    this.language,
    this.uploadProgress = 0.0,
    this.status = UploadTaskStatus.uploading,
    this.lectureId,
    this.errorMessage,
  });

  /// Процент загрузки файла (0–100).
  int get uploadPercent => (uploadProgress * 100).round().clamp(0, 100);

  bool get isUploading => status == UploadTaskStatus.uploading;
  bool get isProcessing => status == UploadTaskStatus.processing;
  bool get isCompleted => status == UploadTaskStatus.completed;
  bool get isFailed => status == UploadTaskStatus.failed;
  bool get canRetry => status == UploadTaskStatus.failed;
}
