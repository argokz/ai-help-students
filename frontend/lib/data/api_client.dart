import 'dart:io';
import 'package:dio/dio.dart';
import '../core/config/app_config.dart';
import '../models/lecture.dart';
import '../models/transcript.dart';
import '../models/summary.dart';
import '../models/chat_message.dart';
import '../models/lecture.dart' show Lecture, LectureSearchResult;
import '../models/auth.dart';
import '../models/note.dart';
import '../models/calendar_event.dart';
import '../models/task.dart';
import 'auth_repository.dart';

class ApiClient {
  final Dio _dio;
  final AuthRepository _auth = authRepository;

  ApiClient() : _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: Duration(seconds: AppConfig.connectTimeout),
    receiveTimeout: Duration(seconds: AppConfig.receiveTimeout),
    headers: {
      'Content-Type': 'application/json',
    },
  )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _auth.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (err, handler) async {
        if (err.response?.statusCode == 401) {
          await _auth.logout();
          // Caller can redirect to login if needed
        }
        handler.next(err);
      },
    ));
  }

  // Auth

  Future<TokenResponse> register({required String email, required String password}) async {
    final response = await _dio.post(
      '/auth/register',
      data: {'email': email, 'password': password},
    );
    return TokenResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TokenResponse> login({required String email, required String password}) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return TokenResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<UserInfo> getMe() async {
    final response = await _dio.get('/auth/me');
    return UserInfo.fromJson(response.data as Map<String, dynamic>);
  }

  /// Вход через Google. Передайте id_token из Google Sign-In.
  Future<TokenResponse> loginWithGoogle(String idToken) async {
    final response = await _dio.post(
      '/auth/google',
      data: {'id_token': idToken},
    );
    return TokenResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // Lectures

  /// Список лекций с опциональным фильтром по предмету и группе.
  /// В ответе также subjects и groups для фильтров в UI.
  Future<LectureListResult> getLectures({
    String? subject,
    String? groupName,
  }) async {
    final response = await _dio.get(
      '/lectures',
      queryParameters: {
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        if (groupName != null && groupName.isNotEmpty) 'group_name': groupName,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final lectures = (data['lectures'] as List)
        .map((l) => Lecture.fromJson(l as Map<String, dynamic>))
        .toList();
    final subjects = (data['subjects'] as List?)?.cast<String>() ?? [];
    final groups = (data['groups'] as List?)?.cast<String>() ?? [];
    return LectureListResult(
      lectures: lectures,
      subjects: subjects,
      groups: groups,
    );
  }

  Future<Lecture> getLecture(String id) async {
    // Для polling используем безопасный таймаут (60 сек)
    // GET /lectures/{id} - это просто чтение из БД, должно быть быстро
    // Но даём запас на случай медленного ответа БД или сетевых задержек
    final response = await _dio.get(
      '/lectures/$id',
      options: Options(
        receiveTimeout: const Duration(seconds: 60),  // Безопасный таймаут для polling
      ),
    );
    return Lecture.fromJson(response.data as Map<String, dynamic>);
  }

  /// URL аудио лекции для воспроизведения (нужен заголовок Authorization).
  static String lectureAudioUrl(String lectureId) {
    return '${AppConfig.apiBaseUrl}/lectures/$lectureId/audio';
  }

  /// Скачать аудио лекции в файл [savePath]. Возвращает путь при успехе.
  Future<String> downloadLectureAudio(
    String lectureId, 
    String savePath, {
    void Function(int, int)? onReceiveProgress,
  }) async {
    await _dio.download(
      '/lectures/$lectureId/audio', 
      savePath,
      onReceiveProgress: onReceiveProgress,
    );
    return savePath;
  }

  /// [onSendProgress] вызывается с (отправлено байт, всего байт).
  /// Для больших файлов используются увеличенные таймауты и повтор при обрыве.
  Future<Lecture> uploadLecture({
    required File audioFile,
    String? title,
    String? language,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        audioFile.path,
        filename: audioFile.path.split('/').last,
      ),
      if (title != null) 'title': title,
      if (language != null) 'language': language,
    });

    const maxAttempts = 3;
    Exception? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _dio.post(
          '/lectures/upload',
          data: formData,
          options: Options(
            headers: {'Content-Type': 'multipart/form-data'},
            sendTimeout: Duration(seconds: AppConfig.uploadSendTimeout),
            receiveTimeout: Duration(seconds: AppConfig.uploadReceiveTimeout),
          ),
          onSendProgress: onSendProgress,
        );
        return Lecture.fromJson(response.data as Map<String, dynamic>);
      } on DioException catch (e) {
        lastError = e;
        final isRetryable = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            (e.error is SocketException);
        if (!isRetryable || attempt == maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
    throw lastError ?? StateError('Upload failed');
  }

  Future<void> deleteLecture(String id) async {
    await _dio.delete('/lectures/$id');
  }

  /// Обновить предмет и/или группу лекции.
  Future<Lecture> updateLecture(
    String id, {
    String? subject,
    String? groupName,
  }) async {
    final response = await _dio.patch(
      '/lectures/$id',
      data: {
        if (subject != null) 'subject': subject,
        if (groupName != null) 'group_name': groupName,
      },
    );
    return Lecture.fromJson(response.data as Map<String, dynamic>);
  }

  /// Умный поиск по названию и тексту транскриптов.
  Future<List<LectureSearchResult>> searchLectures(
    String q, {
    String? subject,
    String? groupName,
    int limit = 50,
  }) async {
    if (q.trim().isEmpty) return [];
    final response = await _dio.get(
      '/lectures/search',
      queryParameters: {
        'q': q,
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        if (groupName != null && groupName.isNotEmpty) 'group_name': groupName,
        'limit': limit,
      },
    );
    final data = response.data as Map<String, dynamic>;
    return (data['results'] as List)
        .map((r) => LectureSearchResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  // Transcript

  Future<Transcript> getTranscript(String lectureId) async {
    final response = await _dio.get('/lectures/$lectureId/transcript');
    return Transcript.fromJson(response.data as Map<String, dynamic>);
  }

  // Summary

  Future<Summary> getSummary(String lectureId, {bool regenerate = false}) async {
    final response = await _dio.get(
      '/lectures/$lectureId/summary',
      queryParameters: {'regenerate': regenerate},
    );
    return Summary.fromJson(response.data as Map<String, dynamic>);
  }

  // Chat

  Future<ChatResponse> sendMessage({
    required String lectureId,
    required String question,
    List<ChatMessage>? history,
  }) async {
    final response = await _dio.post(
      '/lectures/$lectureId/chat',
      data: {
        'question': question,
        if (history != null)
          'history': history.map((m) => m.toJson()).toList(),
      },
    );
    return ChatResponse.fromJson(response.data as Map<String, dynamic>);
  }

  /// Общий чат по всем лекциям.
  Future<GlobalChatResponse> sendGlobalMessage({
    required String question,
    List<ChatMessage>? history,
  }) async {
    final response = await _dio.post(
      '/chat/global',
      data: {
        'question': question,
        if (history != null)
          'history': history.map((m) => m.toJson()).toList(),
      },
    );
    return GlobalChatResponse.fromJson(response.data as Map<String, dynamic>);
  }
  // Notes

  Future<List<Note>> getNotes({String? lectureId, int limit = 50, int offset = 0}) async {
    final response = await _dio.get(
      '/notes',
      queryParameters: {
        if (lectureId != null) 'lecture_id': lectureId,
        'limit': limit,
        'offset': offset,
      },
    );
    return (response.data as List).map((e) => Note.fromJson(e)).toList();
  }

  Future<Note> createNote({
    String? title,
    String? content,
    String? lectureId,
  }) async {
    final response = await _dio.post(
      '/notes',
      data: {
        'title': title,
        'content': content,
        'lecture_id': lectureId,
      },
    );
    return Note.fromJson(response.data);
  }

  Future<Note> getNote(String id) async {
    final response = await _dio.get('/notes/$id');
    return Note.fromJson(response.data);
  }

  Future<Note> updateNote(String id, {String? title, String? content, String? lectureId}) async {
    final response = await _dio.patch(
      '/notes/$id',
      data: {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        if (lectureId != null) 'lecture_id': lectureId,
      },
    );
    return Note.fromJson(response.data);
  }

  Future<void> deleteNote(String id) async {
    await _dio.delete('/notes/$id');
  }

  Future<Note> uploadNoteAudio(String id, File audioFile) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        audioFile.path,
        filename: 'audio.m4a', // Server uses this extension logic
      ),
    });
    final response = await _dio.post(
      '/notes/$id/audio',
      data: formData,
    );
    return Note.fromJson(response.data);
  }
  
  static String noteAudioUrl(String noteId) {
    return '${AppConfig.apiBaseUrl}/notes/$noteId/audio';
  }

  Future<Note> uploadNoteAttachment(String id, File file) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
    });
    final response = await _dio.post(
      '/notes/$id/attachments',
      data: formData,
    );
    return Note.fromJson(response.data);
  }
  
  static String attachmentUrl(String noteId, String attachmentId) {
    return '${AppConfig.apiBaseUrl}/notes/$noteId/attachments/$attachmentId';
  }

  // Calendar

  Future<List<CalendarEvent>> getCalendarEvents({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final response = await _dio.get(
      '/calendar',
      queryParameters: {
        if (startDate != null) 'start_date': startDate.toIso8601String(),
        if (endDate != null) 'end_date': endDate.toIso8601String(),
      },
    );
    return (response.data as List).map((e) => CalendarEvent.fromJson(e)).toList();
  }

  Future<CalendarEvent> createCalendarEvent(CalendarEvent event) async {
    final response = await _dio.post('/calendar', data: event.toJson());
    return CalendarEvent.fromJson(response.data);
  }

  Future<CalendarEvent> getCalendarEvent(String id) async {
    final response = await _dio.get('/calendar/$id');
    return CalendarEvent.fromJson(response.data);
  }

  Future<CalendarEvent> updateCalendarEvent(String id, Map<String, dynamic> updates) async {
    final response = await _dio.patch('/calendar/$id', data: updates);
    return CalendarEvent.fromJson(response.data);
  }

  Future<void> deleteCalendarEvent(String id) async {
    await _dio.delete('/calendar/$id');
  }

  // Task Extraction

  Future<Map<String, dynamic>> extractTasksFromLecture(String lectureId) async {
    final response = await _dio.post('/lectures/$lectureId/extract-tasks');
    return response.data as Map<String, dynamic>;
  }

  Future<CalendarEvent> createEventFromTask(Map<String, dynamic> taskData) async {
    final response = await _dio.post('/calendar/create-from-task', data: taskData);
    return CalendarEvent.fromJson(response.data);
  }

  // Tasks (To-Do List)

  Future<List<Task>> getTasks({
    bool? completed,
    String? lectureId,
    String? priority,
  }) async {
    final response = await _dio.get(
      '/tasks',
      queryParameters: {
        if (completed != null) 'completed': completed,
        if (lectureId != null) 'lecture_id': lectureId,
        if (priority != null) 'priority': priority,
      },
    );
    return (response.data as List).map((e) => Task.fromJson(e)).toList();
  }

  Future<Task> createTask(Task task) async {
    final response = await _dio.post('/tasks', data: task.toJson());
    return Task.fromJson(response.data);
  }

  Future<Task> updateTask(String id, Map<String, dynamic> updates) async {
    final response = await _dio.patch('/tasks/$id', data: updates);
    return Task.fromJson(response.data);
  }

  Future<Task> toggleTaskCompletion(String id) async {
    final response = await _dio.post('/tasks/$id/toggle');
    return Task.fromJson(response.data);
  }

  Future<void> deleteTask(String id) async {
    await _dio.delete('/tasks/$id');
  }

  Future<Task> createTaskFromExtracted(Map<String, dynamic> taskData) async {
    final response = await _dio.post('/tasks/from-extracted', data: taskData);
    return Task.fromJson(response.data);
  }

  Future<void> linkGoogleCalendar(String serverAuthCode) async {
    await _dio.post('/google/link-calendar', data: {'code': serverAuthCode});
  }
}

/// Результат getLectures с списками для фильтров.
class LectureListResult {
  final List<Lecture> lectures;
  final List<String> subjects;
  final List<String> groups;
  LectureListResult({
    required this.lectures,
    required this.subjects,
    required this.groups,
  });
}

final apiClient = ApiClient();
