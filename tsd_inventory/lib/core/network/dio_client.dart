import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Учётные данные Basic Auth.
class BasicCredentials {
  const BasicCredentials(this.login, this.password);
  final String login;
  final String password;

  String get headerValue =>
      'Basic ${base64Encode(utf8.encode('$login:$password'))}';
}

/// HttpClient на dio с BasicAuth + timeout + retry.
class DioClient {
  DioClient({required AppConfig config, required BasicCredentials credentials})
      : _dio = Dio(BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: Duration(seconds: config.connectTimeoutSec),
          receiveTimeout: Duration(seconds: config.receiveTimeoutSec),
          responseType: ResponseType.json,
          headers: {'Accept': 'application/json'},
        )) {
    _dio.interceptors.add(_BasicAuthInterceptor(credentials));
    _dio.interceptors.add(_RetryInterceptor(maxRetries: 2));
  }

  final Dio _dio;

  Future<Response<T>> getJson<T>(String path, {Map<String, dynamic>? query}) =>
      _dio.get<T>(path, queryParameters: query);

  Future<Response<T>> postJson<T>(String path, {Object? body}) =>
      _dio.post<T>(path, data: body);
}

/// Выставляет Authorization: Basic на каждый запрос.
class _BasicAuthInterceptor extends Interceptor {
  _BasicAuthInterceptor(this._creds);
  final BasicCredentials _creds;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = _creds.headerValue;
    handler.next(options);
  }
}

/// Простой retry на сетевые ошибки (connection/timeout/5xx) с backoff.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor({required this.maxRetries});
  final int maxRetries;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra['retryAttempt'] as int?) ?? 0;
    final retriable = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);

    if (attempt < maxRetries && retriable) {
      await Future.delayed(Duration(seconds: attempt + 1));
      try {
        err.requestOptions.extra['retryAttempt'] = attempt + 1;
        final dio = Dio();
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } on DioException catch (e) {
        handler.next(e);
        return;
      }
    }
    handler.next(err);
  }
}
