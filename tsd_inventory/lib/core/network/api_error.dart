import 'package:dio/dio.dart';

/// Типизированная ошибка API для человекочитаемых сообщений.
sealed class ApiError {
  const ApiError();
  String get userMessage;

  /// Маппинг DioException → ApiError.
  factory ApiError.fromDio(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      return const AuthError();
    }
    if (code == 404) {
      return const NotFoundError();
    }
    if (code != null && code >= 500) {
      return ServerError(code: code);
    }
    // Сетевые: connection refused, timeout, socket
    return const NetworkError();
  }
}

class AuthError extends ApiError {
  const AuthError();
  @override
  String get userMessage => 'Неверный логин или пароль';
}

class NetworkError extends ApiError {
  const NetworkError();
  @override
  String get userMessage => 'Нет связи с сервером. Проверьте Wi-Fi';
}

class ServerError extends ApiError {
  final int code;
  const ServerError({required this.code});
  @override
  String get userMessage => 'Ошибка сервера. Код: $code';
}

class NotFoundError extends ApiError {
  const NotFoundError();
  @override
  String get userMessage => 'Не найдено';
}

class ParseError extends ApiError {
  final String detail;
  const ParseError(this.detail);
  @override
  String get userMessage => 'Ошибка обработки данных сервера';
}
