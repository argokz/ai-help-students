import 'package:flutter/material.dart';
import '../features/lectures/lectures_screen.dart';
import '../features/lectures/lecture_detail_screen.dart';
import '../features/recording/recording_screen.dart';
import '../features/transcript/transcript_screen.dart';
import '../features/summary/summary_screen.dart';
import '../features/chat/chat_screen.dart';

class AppRoutes {
  static const String lectures = '/';
  static const String lectureDetail = '/lecture';
  static const String recording = '/recording';
  static const String transcript = '/transcript';
  static const String summary = '/summary';
  static const String chat = '/chat';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case lectures:
        return MaterialPageRoute(
          builder: (_) => const LecturesScreen(),
        );
      
      case lectureDetail:
        final lectureId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => LectureDetailScreen(lectureId: lectureId),
        );
      
      case recording:
        return MaterialPageRoute(
          builder: (_) => const RecordingScreen(),
        );
      
      case transcript:
        final lectureId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => TranscriptScreen(lectureId: lectureId),
        );
      
      case summary:
        final lectureId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => SummaryScreen(lectureId: lectureId),
        );
      
      case chat:
        final lectureId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => ChatScreen(lectureId: lectureId),
        );
      
      default:
        return MaterialPageRoute(
          builder: (_) => const LecturesScreen(),
        );
    }
  }
}
