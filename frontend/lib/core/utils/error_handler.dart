import 'dart:io';
import 'package:dio/dio.dart';

class ErrorHandler {
  static String getMessage(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Превышено время ожидания ответа от сервера.';
        case DioExceptionType.connectionError:
          return 'Нет соединения с интернетом.';
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final data = error.response?.data;
          
          if (statusCode == 401) {
            return 'Ошибка авторизации. Пожалуйста, войдите снова.';
          } else if (statusCode == 403) {
            return 'У вас нет доступа к этому ресурсу.';
          } else if (statusCode == 404) {
            return 'Ресурс не найден.';
          } else if (statusCode == 500) {
            return 'Внутренняя ошибка сервера.';
          }
          
          if (data is Map && data.containsKey('detail')) {
            return data['detail'].toString();
          }
          return 'Ошибка сервера: $statusCode';
        case DioExceptionType.cancel:
          return 'Запрос был отменен.';
        default:
          if (error.error is SocketException) {
            return 'Проверьте подключение к интернету.';
          }
          return 'Произошла неизвестная ошибка связи.';
      }
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}
