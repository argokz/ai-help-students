import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/calendar_event.dart';
import '../models/task.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  
  /// Публичный доступ к notifications для обновления уведомлений записи
  FlutterLocalNotificationsPlugin get notifications => _notifications;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - можно открыть конкретное событие
    // Для этого нужно передать eventId через payload
    print('Notification tapped: ${response.payload}');
  }

  Future<bool> requestPermissions() async {
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    bool? androidGranted;
    bool? iosGranted;

    if (androidPlugin != null) {
      androidGranted = await androidPlugin.requestNotificationsPermission();
    }

    if (iosPlugin != null) {
      iosGranted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    return androidGranted ?? iosGranted ?? false;
  }

  Future<void> scheduleEventReminder(CalendarEvent event) async {
    if (event.remindAt == null) return;

    final now = DateTime.now();
    if (event.remindAt!.isBefore(now)) return; // Не планируем прошедшие напоминания

    await _notifications.zonedSchedule(
      event.id.hashCode, // Unique ID
      event.title,
      event.description ?? 'Событие начнется в ${event.timeRange}',
      tz.TZDateTime.from(event.remindAt!, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'calendar_reminders',
          'Напоминания календаря',
          channelDescription: 'Уведомления о предстоящих событиях',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: event.id,
    );
  }

  Future<void> cancelEventReminder(String eventId) async {
    await _notifications.cancel(eventId.hashCode);
  }

  Future<void> cancelAllReminders() async {
    await _notifications.cancelAll();
  }

  /// Schedule reminder for event start time (e.g., 15 minutes before)
  Future<void> scheduleEventStartReminder(CalendarEvent event, {int minutesBefore = 15}) async {
    final reminderTime = event.startTime.subtract(Duration(minutes: minutesBefore));
    final now = DateTime.now();

    if (reminderTime.isBefore(now)) return;

    await _notifications.zonedSchedule(
      '${event.id}_start'.hashCode,
      'Скоро: ${event.title}',
      'Начало через $minutesBefore минут',
      tz.TZDateTime.from(reminderTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'calendar_reminders',
          'Напоминания календаря',
          channelDescription: 'Уведомления о предстоящих событиях',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: event.id,
    );
  }

  Future<void> scheduleTaskReminder(Task task) async {
    if (task.dueDate == null || task.isCompleted) return;

    // Schedule for 9:00 AM on the due date, or now if it's already past 9:00 AM on due date
    var reminderTime = DateTime(task.dueDate!.year, task.dueDate!.month, task.dueDate!.day, 9, 0);
    
    if (reminderTime.isBefore(DateTime.now())) {
      // If today is the due date and it's past 9:00 AM, don't schedule for the past
      // Maybe schedule for 1 hour from now or just skip
      return;
    }

    await _notifications.zonedSchedule(
      task.id.hashCode,
      'Дедлайн: ${task.title}',
      'Сегодня срок сдачи задания',
      tz.TZDateTime.from(reminderTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Напоминания о задачах',
          channelDescription: 'Уведомления о дедлайнах',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: task.id,
    );
  }

  Future<void> cancelTaskReminder(String taskId) async {
    await _notifications.cancel(taskId.hashCode);
  }
}

final notificationService = NotificationService();
