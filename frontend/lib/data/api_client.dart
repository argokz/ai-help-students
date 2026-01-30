import 'dart:io';
import 'package:dio/dio.dart';
import '../models/lecture.dart';
import '../models/transcript.dart';
import '../models/summary.dart';
import '../models/chat_message.dart';

class ApiClient {
  static const String _baseUrl = 'http://10.0.2.2:8000/api'; // Android emulator
  // For physical device, use your computer's IP address
  // static const String _baseUrl = 'http://192.168.1.x:8000/api';
  
  final Dio _dio;

  ApiClient() : _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'Content-Type': 'application/json',
    },
  ));

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

  Future<Lecture> uploadLecture({
    required File audioFile,
    String? title,
    String? language,
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

// Global instance
final apiClient = ApiClient();
