import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Простой HttpClientAdapter для тестов: возвращает заданный [response] или
/// бросает [error]. Не делает реальных HTTP-запросов.
class MockAdapter implements HttpClientAdapter {
  ResponseBody? response;
  DioException? error;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (error != null) throw error!;
    if (response != null) return response!;
    throw StateError('MockAdapter: ни response, ни error не заданы');
  }

  @override
  void close({bool force = false}) {}
}
