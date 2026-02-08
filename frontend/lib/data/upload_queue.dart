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
  static const _maxPollingDuration = Duration(minutes: 30); // Максимальное время polling
  static const _maxConsecutiveErrors = 5; // Максимум ошибок подряд перед остановкой
  final Map<String, Timer> _pollTimers = {};
  final Map<String, DateTime> _pollingStartTimes = {}; // Когда начали polling
  final Map<String, int> _consecutiveErrors = {}; // Счётчик ошибок подряд
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
  /// Если для того же [filePath] уже есть задача в очереди: при статусе failed — повторяем её (retry), иначе не дублируем.
  void addTask({
    required String filePath,
    String? title,
    String? language,
  }) {
    for (final t in _tasks) {
      if (t.filePath == filePath) {
        if (t.status == UploadTaskStatus.failed) {
          retry(t);
        }
        return;
      }
    }
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

    _pollingStartTimes[task.id] = DateTime.now();
    _consecutiveErrors[task.id] = 0;

    void poll() async {
      // Проверка таймаута
      final startTime = _pollingStartTimes[task.id];
      if (startTime != null && DateTime.now().difference(startTime) > _maxPollingDuration) {
        _stopPolling(task, 'Превышено время ожидания обработки (${_maxPollingDuration.inMinutes} минут)');
        return;
      }

      try {
        final lecture = await _api.getLecture(lectureId);
        // Сбрасываем счётчик ошибок при успешном запросе
        _consecutiveErrors[task.id] = 0;
        
        if (lecture.status == 'completed') {
          _stopPolling(task);
          task.status = UploadTaskStatus.completed;
          _notifyListenersSafely();
          onLectureCompleted?.call();
          _removeTaskLater(task);
          return;
        }
        if (lecture.status == 'failed') {
          _stopPolling(task, 'Ошибка обработки на сервере');
          task.status = UploadTaskStatus.failed;
          task.errorMessage = 'Ошибка обработки на сервере';
          _notifyListenersSafely();
          return;
        }
        if (lecture.status == 'processing') {
          task.processingProgress = lecture.processingProgress;
          _notifyListenersSafely();
        }
      } catch (e) {
        // Увеличиваем счётчик ошибок
        final errorCount = (_consecutiveErrors[task.id] ?? 0) + 1;
        _consecutiveErrors[task.id] = errorCount;
        
        // Если слишком много ошибок подряд - останавливаем polling
        if (errorCount >= _maxConsecutiveErrors) {
          final errorMsg = e.toString().contains('timeout') || e.toString().contains('Timeout')
              ? 'Сервер не отвечает. Проверьте подключение.'
              : 'Ошибка соединения с сервером';
          _stopPolling(task, errorMsg);
          return;
        }
        
        // Логируем ошибку, но продолжаем polling
        debugPrint('Polling error for task ${task.id}: $e (attempt $errorCount/$_maxConsecutiveErrors)');
      }
    }

    poll();
    final timer = Timer.periodic(_pollInterval, (_) => poll());
    _pollTimers[task.id] = timer;
  }

  void _stopPolling(UploadTask task, [String? errorMessage]) {
    _pollTimers[task.id]?.cancel();
    _pollTimers.remove(task.id);
    _pollingStartTimes.remove(task.id);
    _consecutiveErrors.remove(task.id);
    
    if (errorMessage != null && task.status != UploadTaskStatus.completed) {
      task.status = UploadTaskStatus.failed;
      task.errorMessage = errorMessage;
      _notifyListenersSafely();
    }
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
    _stopPolling(task);
    _tasks.remove(task);
    notifyListeners();
  }
}

final uploadQueue = UploadQueueNotifier();
