import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/update/data/update_repository.dart';

import '../../../helpers/mock_adapter.dart';

void main() {
  late Dio dio;
  late MockAdapter adapter;
  late UpdateRepository repo;

  setUp(() {
    dio = Dio();
    adapter = MockAdapter();
    dio.httpClientAdapter = adapter;
    // Cookie-логин на портал в тестах не выполняем — отдаём фиксированную cookie.
    repo = UpdateRepository(
      dio: dio,
      login: (_, __, ___) async => 'wordpress_logged_in_test=test',
    );
  });

  group('checkForUpdate', () {
    test('корректный манифест → Success(VersionManifest)', () async {
      adapter.response = ResponseBody.fromString(
        jsonEncode({
          'versionName': '0.2.0',
          'versionCode': 2,
          'apkFileId': 58930,
          'releaseNotes': 'Новое',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
      final res = await repo.checkForUpdate('http://host/manifest.json');

      expect(res, isA<Success>());
      final m = (res as Success).value;
      expect(m.versionCode, 2);
      expect(m.versionName, '0.2.0');
      expect(m.apkFileId, 58930);
    });

    test('пустой URL → Failure (фича выключена)', () async {
      final res = await repo.checkForUpdate('');
      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });

    test('сеть недоступна (connectionError) → Failure(NetworkError)', () async {
      adapter.error = DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      );
      final res = await repo.checkForUpdate('http://host/manifest.json');
      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });

    test('500 → Failure(ServerError)', () async {
      adapter.error = DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 500,
        ),
        type: DioExceptionType.badResponse,
      );
      final res = await repo.checkForUpdate('http://host/manifest.json');
      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ServerError>());
    });

    test('не JSON-объект (массив) → Failure(ParseError)', () async {
      adapter.response = ResponseBody.fromString(
        '[1, 2, 3]',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
      final res = await repo.checkForUpdate('http://host/manifest.json');
      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ParseError>());
    });
  });

  group('downloadApk', () {
    test('успех → файл создан с содержимым ответа', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      adapter.response = ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentLengthHeader: ['${bytes.length}'],
        },
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(
        'http://host/app.apk',
        targetDir: tmpDir,
      );

      expect(res, isA<Success>());
      final file = (res as Success).value;
      expect(await file.exists(), isTrue);
      expect(await file.length(), bytes.length);
      await tmpDir.delete(recursive: true);
    });

    test('сеть недоступна → Failure', () async {
      adapter.error = DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(
        'http://host/app.apk',
        targetDir: tmpDir,
      );

      expect(res, isA<Failure>());
      await tmpDir.delete(recursive: true);
    });
  });
}
