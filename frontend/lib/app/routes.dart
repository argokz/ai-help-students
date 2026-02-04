import 'package:flutter/material.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/lectures/lectures_screen.dart';
import '../features/lectures/lecture_detail_screen.dart';
import '../features/recording/recording_screen.dart';
import '../features/transcript/transcript_screen.dart';
import '../features/summary/summary_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/global_chat_screen.dart';

class AppRoutes {
  static const String login = '/';
  static const String register = '/register';
  static const String lectures = '/lectures';
  static const String lectureDetail = '/lecture';
  static const String recording = '/recording';
  static const String transcript = '/transcript';
  static const String summary = '/summary';
  static const String chat = '/chat';
  static const String globalChat = '/global-chat';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        );
      case register:
        return MaterialPageRoute(
          builder: (_) => const RegisterScreen(),
        );
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
      case globalChat:
        return MaterialPageRoute(
          builder: (_) => const GlobalChatScreen(),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        );
    }
  }
}
