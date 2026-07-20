import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Простой HttpClientAdapter для тестов: возвращает заданный [response] или
/// бросает [error]. Не делает реальных HTTP-запросов.
///
/// Для проверок заголовков/метода/пути каждый запрос фиксируется в [requests].
class MockAdapter implements HttpClientAdapter {
  MockAdapter({this.recordRequests = false});

  ResponseBody? response;
  DioException? error;

  /// Записывать ли каждый запрос в [requests] (для инспекции заголовков).
  final bool recordRequests;

  /// Зафиксированные запросы (в порядке поступления), если [recordRequests].
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (recordRequests) requests.add(options);
    if (error != null) throw error!;
    if (response != null) return response!;
    throw StateError('MockAdapter: ни response, ни error не заданы');
  }

  @override
  void close({bool force = false}) {}
}
