import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import 'routes.dart';

class LectureAssistantApp extends StatelessWidget {
  const LectureAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ассистент Лекций',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      initialRoute: AppRoutes.lectures,
      onGenerateRoute: AppRoutes.generateRoute,
    );
  }
}
