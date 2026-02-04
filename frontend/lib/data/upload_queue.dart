import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/upload_task.dart' show UploadTask, UploadTaskStatus;
import 'api_client.dart';

/// Глобальная очередь загрузок. Запускает загрузку в фоне, обновляет прогресс,
/// после успешной отправки опрашивает статус лекции до completed/failed.
class UploadQueueNotifier extends ChangeNotifier {
  final List<UploadTask> _tasks = [];
  final ApiClient _api = apiClient;
  static const _pollInterval = Duration(seconds: 5);
  final Map<String, Timer> _pollTimers = {};
  /// Вызывается, когда лекция перешла в completed — можно обновить список.
  void Function()? onLectureCompleted;

  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  /// Уведомить слушателей в следующем фрейме, чтобы не вызывать _dependents.isEmpty
  /// при уведомлении из таймера/async (после dispose виджета).
  void _notifyListenersSafely() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }

  /// Добавить задачу и сразу запустить загрузку в фоне.
  void addTask({
    required String filePath,
    String? title,
    String? language,
  }) {
    final id = '${DateTime.now().millisecondsSinceEpoch}_${filePath.hashCode}';
    final task = UploadTask(
      id: id,
      filePath: filePath,
      title: title,
      language: language,
    );
    _tasks.add(task);
    notifyListeners();
    _runUpload(task);
  }

  void _runUpload(UploadTask task) async {
    final file = File(task.filePath);
    if (!file.existsSync()) {
      _setFailed(task, 'Файл не найден', fromAsync: true);
      return;
    }

    void onProgress(int sent, int total) {
      if (total > 0) {
        task.uploadProgress = sent / total;
        _notifyListenersSafely();
      }
    }

    try {
      final lecture = await _api.uploadLecture(
        audioFile: file,
        title: task.title,
        language: task.language,
        onSendProgress: onProgress,
      );

      task.uploadProgress = 1.0;
      task.lectureId = lecture.id;
      task.status = UploadTaskStatus.processing;
      task.processingStartedAt = DateTime.now();
      task.errorMessage = null;
      _notifyListenersSafely();

      _startPolling(task);
    } catch (e, st) {
      task.status = UploadTaskStatus.failed;
      task.errorMessage = e.toString();
      _notifyListenersSafely();
      debugPrint('Upload failed: $e $st');
    }
  }

  void _startPolling(UploadTask task) {
    final lectureId = task.lectureId;
    if (lectureId == null) return;

    void poll() async {
      try {
        final lecture = await _api.getLecture(lectureId);
        if (lecture.status == 'completed') {
          _pollTimers[task.id]?.cancel();
          _pollTimers.remove(task.id);
          task.status = UploadTaskStatus.completed;
          _notifyListenersSafely();
          onLectureCompleted?.call();
          _removeTaskLater(task);
          return;
        }
        if (lecture.status == 'failed') {
          _pollTimers[task.id]?.cancel();
          _pollTimers.remove(task.id);
          task.status = UploadTaskStatus.failed;
          task.errorMessage = 'Ошибка обработки на сервере';
          _notifyListenersSafely();
          return;
        }
        if (lecture.status == 'processing') {
          task.processingProgress = lecture.processingProgress;
          _notifyListenersSafely();
        }
      } catch (_) {}
    }

    poll();
    final timer = Timer.periodic(_pollInterval, (_) => poll());
    _pollTimers[task.id] = timer;
  }

  void _removeTaskLater(UploadTask task) {
    Future.delayed(const Duration(milliseconds: 800), () {
      _tasks.remove(task);
      _notifyListenersSafely();
    });
  }

  void _setFailed(UploadTask task, String message, {bool fromAsync = false}) {
    task.status = UploadTaskStatus.failed;
    task.errorMessage = message;
    if (fromAsync) {
      _notifyListenersSafely();
    } else {
      notifyListeners();
    }
  }

  /// Повторить загрузку для задачи в состоянии failed.
  void retry(UploadTask task) {
    if (!task.canRetry) return;
    task.uploadProgress = 0.0;
    task.status = UploadTaskStatus.uploading;
    task.errorMessage = null;
    task.lectureId = null;
    notifyListeners();
    _runUpload(task);
  }

  void remove(UploadTask task) {
    _pollTimers[task.id]?.cancel();
    _pollTimers.remove(task.id);
    _tasks.remove(task);
    notifyListeners();
  }
}

final uploadQueue = UploadQueueNotifier();
