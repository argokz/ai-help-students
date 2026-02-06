import 'package:flutter/material.dart';
import 'app/app.dart';
import 'data/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications
  await notificationService.initialize();
  await notificationService.requestPermissions();
  
  runApp(const LectureAssistantApp());
}
