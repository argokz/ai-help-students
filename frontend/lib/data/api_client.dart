import 'dart:io';
import 'package:dio/dio.dart';
import '../core/config/app_config.dart';
import '../models/lecture.dart';
import '../models/transcript.dart';
import '../models/summary.dart';
import '../models/chat_message.dart';
import '../models/lecture.dart' show Lecture, LectureSearchResult;
import '../models/auth.dart';
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
    final response = await _dio.get('/lectures/$id');
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
