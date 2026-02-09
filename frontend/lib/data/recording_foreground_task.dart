import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Минимальный TaskHandler для foreground-сервиса записи.
/// Запись идёт в основном isolate (RecordingService); сервис нужен только
/// чтобы при блокировке экрана Android не приостанавливал процесс и микрофон.
@pragma('vm:entry-point')
void startRecordingForegroundTask() {
  FlutterForegroundTask.setTaskHandler(_RecordingForegroundTaskHandler());
}

class _RecordingForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}

/// Инициализация foreground task для записи (вызвать из main перед runApp).
Future<void> initRecordingForegroundTask() async {
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'recording_foreground',
      channelName: 'Запись лекции',
      channelDescription: 'Уведомление при записи в фоне (экран заблокирован)',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

/// Запуск foreground-сервиса с типом microphone (перед началом записи).
Future<bool> startRecordingForegroundService() async {
  if (!Platform.isAndroid) return true;
  final result = await FlutterForegroundTask.startService(
    serviceId: 300,
    notificationTitle: 'Идёт запись...',
    notificationText: 'Нажмите, чтобы открыть приложение',
    callback: startRecordingForegroundTask,
    serviceTypes: [ForegroundServiceTypes.microphone],
  );
  return result is ServiceRequestSuccess;
}

/// Остановка foreground-сервиса (после остановки записи).
Future<void> stopRecordingForegroundService() async {
  if (!Platform.isAndroid) return;
  await FlutterForegroundTask.stopService();
}

/// Обновить текст уведомления (например, длительность записи).
void updateRecordingNotificationText(String text) {
  if (!Platform.isAndroid) return;
  FlutterForegroundTask.updateService(notificationText: text);
}
