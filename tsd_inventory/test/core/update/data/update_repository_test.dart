import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/update/data/update_repository.dart';

import '../../../helpers/mock_adapter.dart';

/// Конфиг с одним хостом, чтобы failover не дублировал запросы в тестах.
const _testConfig = AppConfig(baseUrl: 'http://test-host/erp/');

/// Авторизованный клиент 1С + его MockAdapter (Basic Auth на месте).
class _Authed {
  _Authed() : adapter = MockAdapter(recordRequests: true), dio = Dio() {
    dio.httpClientAdapter = adapter;
    client = DioClient(
      config: _testConfig,
      credentials: const BasicCredentials('user', 'pass'),
      dio: dio,
    );
  }
  final MockAdapter adapter;
  final Dio dio;
  late final DioClient client;
}

Dio _dioWith(MockAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  group('checkForUpdate (через защищённый endpoint 1С)', () {
    test('корректный манифест → Success(VersionManifest)', () async {
      final a = _Authed();
      a.adapter.response = ResponseBody.fromString(
        jsonEncode({
          'versionName': '0.2.6',
          'versionCode': 8,
          'apkUrl': 'https://storage.example/file.apk?sig=abc',
          'urlExpiresInSec': 600,
          'sha256': 'deadbeef',
          'releaseNotes': 'Новое',
          'required': false,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
      final repo = UpdateRepository(client: a.client, downloadDio: Dio());

      final res = await repo.checkForUpdate('hs/inventory/update');

      expect(res, isA<Success>());
      final m = (res as Success).value;
      expect(m.versionCode, 8);
      expect(m.versionName, '0.2.6');
      expect(m.apkUrl, 'https://storage.example/file.apk?sig=abc');
      expect(m.sha256, 'deadbeef');
    });

    test(
      'запрос идёт под Basic Auth, без WordPress cookies/X-Update-Token',
      () async {
        final a = _Authed();
        a.adapter.response = ResponseBody.fromString(
          jsonEncode({}),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
        final repo = UpdateRepository(client: a.client, downloadDio: Dio());

        await repo.checkForUpdate('hs/inventory/update');

        final req = a.adapter.requests.first;
        expect(req.headers['Authorization']?.startsWith('Basic '), isTrue);
        expect(req.headers['Cookie'], isNull);
        expect(req.headers['X-Update-Token'], isNull);
      },
    );

    test('пустой URL → Failure (фича выключена)', () async {
      final a = _Authed();
      final repo = UpdateRepository(client: a.client, downloadDio: Dio());
      final res = await repo.checkForUpdate('');
      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });

    test('сеть недоступна (connectionError) → Failure(NetworkError)', () async {
      final a = _Authed();
      a.adapter.error = DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      );
      final repo = UpdateRepository(client: a.client, downloadDio: Dio());

      final res = await repo.checkForUpdate('hs/inventory/update');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });

    test('401 → Failure(AuthError)', () async {
      final a = _Authed();
      a.adapter.error = DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 401,
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = UpdateRepository(client: a.client, downloadDio: Dio());

      final res = await repo.checkForUpdate('hs/inventory/update');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<AuthError>());
    });

    test('502 от сервиса обновлений → Failure(ServerError)', () async {
      final a = _Authed();
      a.adapter.error = DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 502,
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = UpdateRepository(client: a.client, downloadDio: Dio());

      final res = await repo.checkForUpdate('hs/inventory/update');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ServerError>());
    });

    test('не JSON-объект (массив) → Failure(ParseError)', () async {
      final a = _Authed();
      a.adapter.response = ResponseBody.fromString(
        '[1, 2, 3]',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
      final repo = UpdateRepository(client: a.client, downloadDio: Dio());

      final res = await repo.checkForUpdate('hs/inventory/update');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ParseError>());
    });

    test('итоговый URL корректно склеен (нет дублирования baseUrl)', () async {
      // Регрессия: относительный путь должен склеиваться с baseUrl один раз,
      // а не дважды (раньше передавали полный URL → dio делал baseUrl+url).
      final a = _Authed();
      a.adapter.response = ResponseBody.fromString(
        jsonEncode({}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
      final repo = UpdateRepository(client: a.client, downloadDio: Dio());

      await repo.checkForUpdate('hs/inventory/update');

      final req = a.adapter.requests.first;
      // Склейка: 'http://test-host/erp/' + 'hs/inventory/update'
      // → 'http://test-host/erp/hs/inventory/update' (ровно один baseUrl).
      expect(req.path, 'http://test-host/erp/hs/inventory/update');
      // baseUrl не должен встречаться дважды (регрессия найденного бага).
      expect('http://test-host/erp/'.allMatches(req.path).length, 1);
    });
  });

  group('downloadApk', () {
    test('успех + SHA-256 совпал → Success(файл с содержимым)', () async {
      final a = _Authed();
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final expectedHash = sha256.convert(bytes).toString();
      final downloadAdapter = MockAdapter(recordRequests: true);
      final repo = UpdateRepository(
        client: a.client,
        downloadDio: _dioWith(downloadAdapter),
      );
      downloadAdapter.response = ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentLengthHeader: ['${bytes.length}'],
        },
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(
        'https://storage.example/file.apk?sig=abc',
        sha256: expectedHash,
        targetDir: tmpDir,
      );

      expect(res, isA<Success>());
      final file = (res as Success).value;
      expect(await file.exists(), isTrue);
      expect(await file.length(), bytes.length);
      await tmpDir.delete(recursive: true);
    });

    test('скачивание без Basic Auth/cookies/X-Update-Token', () async {
      final a = _Authed();
      final bytes = Uint8List.fromList([1, 2, 3]);
      final expectedHash = sha256.convert(bytes).toString();
      final downloadAdapter = MockAdapter(recordRequests: true);
      final repo = UpdateRepository(
        client: a.client,
        downloadDio: _dioWith(downloadAdapter),
      );
      downloadAdapter.response = ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentLengthHeader: ['${bytes.length}'],
        },
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      await repo.downloadApk(
        'https://storage.example/file.apk?sig=abc',
        sha256: expectedHash,
        targetDir: tmpDir,
      );

      final req = downloadAdapter.requests.first;
      // Подписанная ссылка самодостаточна — никаких учётных данных.
      expect(req.headers['Authorization'], isNull);
      expect(req.headers['Cookie'], isNull);
      expect(req.headers['X-Update-Token'], isNull);
      await tmpDir.delete(recursive: true);
    });

    test(
      'SHA-256 несовпадение → Failure(IntegrityError) и файл удалён',
      () async {
        final a = _Authed();
        final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
        final downloadAdapter = MockAdapter(recordRequests: true);
        final repo = UpdateRepository(
          client: a.client,
          downloadDio: _dioWith(downloadAdapter),
        );
        downloadAdapter.response = ResponseBody.fromBytes(
          bytes,
          200,
          headers: {
            Headers.contentLengthHeader: ['${bytes.length}'],
          },
        );
        final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

        final res = await repo.downloadApk(
          'https://storage.example/file.apk?sig=abc',
          sha256: '0' * 64, // заведомо неверный хеш
          targetDir: tmpDir,
        );

        expect(res, isA<Failure>());
        expect((res as Failure).error, isA<IntegrityError>());
        final file = File('${tmpDir.path}/tsd_update.apk');
        expect(await file.exists(), isFalse);
        await tmpDir.delete(recursive: true);
      },
    );

    test('пустой sha256 → Failure без скачивания', () async {
      final a = _Authed();
      final downloadAdapter = MockAdapter(recordRequests: true);
      final repo = UpdateRepository(
        client: a.client,
        downloadDio: _dioWith(downloadAdapter),
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(
        'https://storage.example/file.apk?sig=abc',
        sha256: '',
        targetDir: tmpDir,
      );

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ParseError>());
      expect(downloadAdapter.requests, isEmpty);
      await tmpDir.delete(recursive: true);
    });

    test('пустой apkUrl → Failure без скачивания', () async {
      final a = _Authed();
      final downloadAdapter = MockAdapter(recordRequests: true);
      final repo = UpdateRepository(
        client: a.client,
        downloadDio: _dioWith(downloadAdapter),
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk('', sha256: 'abc', targetDir: tmpDir);

      expect(res, isA<Failure>());
      expect(downloadAdapter.requests, isEmpty);
      await tmpDir.delete(recursive: true);
    });

    test('сеть недоступна при скачивании → Failure(NetworkError)', () async {
      final a = _Authed();
      final downloadAdapter = MockAdapter();
      final repo = UpdateRepository(
        client: a.client,
        downloadDio: _dioWith(downloadAdapter),
      );
      downloadAdapter.error = DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(
        'https://storage.example/file.apk?sig=abc',
        sha256: 'abc',
        targetDir: tmpDir,
      );

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
      await tmpDir.delete(recursive: true);
    });

    test('истёкшая подписанная ссылка (403) → Failure', () async {
      final a = _Authed();
      final downloadAdapter = MockAdapter();
      final repo = UpdateRepository(
        client: a.client,
        downloadDio: _dioWith(downloadAdapter),
      );
      downloadAdapter.error = DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 403,
        ),
        type: DioExceptionType.badResponse,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(
        'https://storage.example/file.apk?sig=expired',
        sha256: 'abc',
        targetDir: tmpDir,
      );

      expect(res, isA<Failure>());
      await tmpDir.delete(recursive: true);
    });
  });
}
