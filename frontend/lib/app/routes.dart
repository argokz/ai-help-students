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
import '../features/profile/profile_screen.dart';
import '../features/recordings/local_recordings_screen.dart';
import '../features/notes/notes_screen.dart';
import '../features/notes/note_detail_screen.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/calendar/calendar_event_detail_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/tasks/task_detail_screen.dart';

class AppRoutes {
  static const String login = '/';
  static const String register = '/register';
  static const String lectures = '/lectures';
  static const String lectureDetail = '/lecture';
  static const String recording = '/recording';
  static const String localRecordings = '/local-recordings';
  static const String transcript = '/transcript';
  static const String summary = '/summary';
  static const String chat = '/chat';
  static const String globalChat = '/global-chat';
  static const String profile = '/profile';
  static const String notes = '/notes';
  static const String noteDetail = '/note-detail';
  static const String calendar = '/calendar';
  static const String calendarEventDetail = '/calendar-event-detail';
  static const String tasks = '/tasks';
  static const String taskDetail = '/task-detail';

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
      case localRecordings:
        return MaterialPageRoute(
          builder: (_) => const LocalRecordingsScreen(),
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
      case profile:
        return MaterialPageRoute(
          builder: (_) => const ProfileScreen(),
        );
      case notes:
        return MaterialPageRoute(
          builder: (_) => const NotesScreen(),
        );
      case noteDetail:
        final args = settings.arguments as String?; // noteId or null
        return MaterialPageRoute(
          builder: (_) => NoteDetailScreen(noteId: args),
        );
      case calendar:
        return MaterialPageRoute(
          builder: (_) => const CalendarScreen(),
        );
      case calendarEventDetail:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => CalendarEventDetailScreen(
            eventId: args?['eventId'],
            preselectedDate: args?['date'],
          ),
        );
      case tasks:
        return MaterialPageRoute(
          builder: (_) => const TasksScreen(),
        );
      case taskDetail:
        final args = settings.arguments as String?; // taskId
        return MaterialPageRoute(
          builder: (_) => TaskDetailScreen(taskId: args),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        );
    }
  }
}
