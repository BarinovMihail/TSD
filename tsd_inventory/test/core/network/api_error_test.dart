import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/network/api_error.dart';

DioException _err(int? statusCode,
    {DioExceptionType type = DioExceptionType.badResponse}) {
  final res = statusCode == null
      ? null
      : Response<void>(requestOptions: RequestOptions(), statusCode: statusCode);
  return DioException(
      requestOptions: RequestOptions(), response: res, type: type);
}

void main() {
  test('401 → AuthError', () {
    expect(ApiError.fromDio(_err(401)), isA<AuthError>());
  });
  test('403 → AuthError', () {
    expect(ApiError.fromDio(_err(403)), isA<AuthError>());
  });
  test('404 → NotFoundError', () {
    expect(ApiError.fromDio(_err(404)), isA<NotFoundError>());
  });
  test('500 → ServerError', () {
    final e = ApiError.fromDio(_err(500)) as ServerError;
    expect(e.code, 500);
  });
  test('503 → ServerError', () {
    expect(ApiError.fromDio(_err(503)), isA<ServerError>());
  });
  test('connection timeout → NetworkError', () {
    final e = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionTimeout,
    );
    expect(ApiError.fromDio(e), isA<NetworkError>());
  });
  test('no response (socket) → NetworkError', () {
    expect(ApiError.fromDio(_err(null)), isA<NetworkError>());
  });
}
