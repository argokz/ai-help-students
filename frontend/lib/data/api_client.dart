import 'dart:io';
import 'package:dio/dio.dart';
import '../core/config/app_config.dart';
import '../models/lecture.dart';
import '../models/transcript.dart';
import '../models/summary.dart';
import '../models/chat_message.dart';
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

  Future<List<Lecture>> getLectures() async {
    final response = await _dio.get('/lectures');
    final data = response.data as Map<String, dynamic>;
    final lectures = (data['lectures'] as List)
        .map((l) => Lecture.fromJson(l as Map<String, dynamic>))
        .toList();
    return lectures;
  }

  Future<Lecture> getLecture(String id) async {
    final response = await _dio.get('/lectures/$id');
    return Lecture.fromJson(response.data as Map<String, dynamic>);
  }

  /// [onSendProgress] вызывается с (отправлено байт, всего байт).
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

    final response = await _dio.post(
      '/lectures/upload',
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
      ),
      onSendProgress: onSendProgress,
    );

    return Lecture.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteLecture(String id) async {
    await _dio.delete('/lectures/$id');
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
}

final apiClient = ApiClient();
