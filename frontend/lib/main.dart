import 'package:flutter/material.dart';
import 'app/app.dart';
import 'data/notification_service.dart';
import 'data/recording_foreground_task.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications
  await notificationService.initialize();
  await notificationService.requestPermissions();
  // Foreground task для записи при заблокированном экране (Android)
  await initRecordingForegroundTask();
  
  runApp(const LectureAssistantApp());
}
