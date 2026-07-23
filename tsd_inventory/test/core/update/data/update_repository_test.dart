import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/update/data/update_repository.dart';
import 'package:tsd_inventory/core/update/data/yandex_disk_update_config.dart';
import 'package:tsd_inventory/core/update/domain/version_manifest.dart';

const _testConfig = YandexDiskUpdateConfig(
  publicKey: 'https://disk.yandex.ru/d/test',
  manifestPath: 'manifest.json',
  apiBase: 'https://cloud-api.yandex.net/v1/disk',
);

const _fakeDownloaderUrl = 'https://downloader.disk.yandex.ru/disk/fake-test';

/// Адаптер, маршрутизирующий запросы по URL:
/// - к эндпоинту `public/resources/download` (resolve) → [resolveJson] или
///   [resolveError];
/// - к скачиванию файла по выданному href → [downloadBytes] (или
///   [downloadError]).
///
/// Записывает все запросы в [requests] (для проверки отсутствия авторизации).
class _DiskMockAdapter implements HttpClientAdapter {
  _DiskMockAdapter({this.recordRequests = false});

  /// Тело ответа resolve (JSON как строка). По умолчанию отдаёт фейковый href.
  String resolveJson = jsonEncode({'href': _fakeDownloaderUrl});

  /// Ошибка на этапе resolve (приоритет над [resolveJson]).
  DioException? resolveError;

  /// Байты, отдаваемые «скачиванием» (манифест или zip).
  List<int> downloadBytes = const [];

  /// Ошибка на этапе скачивания (приоритет над [downloadBytes]).
  DioException? downloadError;

  final bool recordRequests;
  final List<RequestOptions> requests = [];

  RequestOptions? _last;
  String get currentPath => _last?.path ?? '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _last = options;
    if (recordRequests) requests.add(options);
    if (options.path.contains('public/resources/download')) {
      if (resolveError != null) throw resolveError!;
      return ResponseBody.fromString(
        resolveJson,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    // Иначе — «скачивание» файла по выданному href.
    if (downloadError != null) throw downloadError!;
    return ResponseBody.fromBytes(
      downloadBytes,
      200,
      headers: {
        Headers.contentLengthHeader: ['${downloadBytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Упаковать [apkBytes] в zip-архив с единственным .apk.
List<int> _zipWithApk(Uint8List apkBytes, {String name = 'app-release.apk'}) {
  final archive = Archive()..addFile(
    ArchiveFile(name, apkBytes.length, apkBytes),
  );
  return ZipEncoder().encode(archive);
}

UpdateRepository _repo(_DiskMockAdapter adapter) =>
    UpdateRepository(config: _testConfig, dio: _dioWith(adapter));

Dio _dioWith(HttpClientAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  group('checkForUpdate (через публичный API Диска)', () {
    test('корректный манифест → Success(VersionManifest)', () async {
      final adapter = _DiskMockAdapter();
      adapter.downloadBytes = utf8.encode(
        jsonEncode({
          'versionName': '0.2.6',
          'versionCode': 8,
          'apkPath': 'releases/tsd-inventory-0.2.6-8.zip',
          'sha256': 'deadbeef',
          'releaseNotes': 'Новое',
          'required': false,
        }),
      );
      final repo = _repo(adapter);

      final res = await repo.checkForUpdate();

      expect(res, isA<Success>());
      final m = (res as Success).value as VersionManifest;
      expect(m.versionCode, 8);
      expect(m.versionName, '0.2.6');
      expect(m.apkPath, 'releases/tsd-inventory-0.2.6-8.zip');
      expect(m.sha256, 'deadbeef');
    });

    test('запрос идёт БЕЗ авторизации (публичная папка)', () async {
      final adapter = _DiskMockAdapter(recordRequests: true);
      adapter.downloadBytes = utf8.encode(jsonEncode({}));
      final repo = _repo(adapter);

      await repo.checkForUpdate();

      for (final req in adapter.requests) {
        expect(req.headers['Authorization'], isNull);
      }
    });

    test('путь к файлу передаётся с ведущим /', () async {
      // Регрессия: публичный API Диска требует path с ведущим слэшем.
      final adapter = _DiskMockAdapter(recordRequests: true);
      adapter.downloadBytes = utf8.encode(jsonEncode({}));
      final repo = _repo(adapter);

      await repo.checkForUpdate();

      final resolveReq = adapter.requests.firstWhere(
        (r) => r.path.contains('public/resources/download'),
      );
      expect(resolveReq.queryParameters['path'], '/manifest.json');
      expect(resolveReq.queryParameters['public_key'], _testConfig.publicKey);
    });

    test('сеть недоступна на resolve (connectionError) → Failure(NetworkError)',
        () async {
      final adapter = _DiskMockAdapter();
      adapter.resolveError = DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      );
      final repo = _repo(adapter);

      final res = await repo.checkForUpdate();

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });

    test('404 (папка/манифест не найдены) → Failure(NotFoundError)', () async {
      final adapter = _DiskMockAdapter();
      adapter.resolveError = DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = _repo(adapter);

      final res = await repo.checkForUpdate();

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NotFoundError>());
    });

    test('502 от Диска → Failure(ServerError)', () async {
      final adapter = _DiskMockAdapter();
      adapter.resolveError = DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 502,
        ),
        type: DioExceptionType.badResponse,
      );
      final repo = _repo(adapter);

      final res = await repo.checkForUpdate();

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ServerError>());
    });

    test('манифест не JSON-объект (массив) → Failure(ParseError)', () async {
      final adapter = _DiskMockAdapter();
      adapter.downloadBytes = utf8.encode('[1, 2, 3]');
      final repo = _repo(adapter);

      final res = await repo.checkForUpdate();

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ParseError>());
    });

    test('в ответе resolve нет href → Failure(ParseError)', () async {
      final adapter = _DiskMockAdapter();
      adapter.resolveJson = jsonEncode({'method': 'GET'}); // без href
      final repo = _repo(adapter);

      final res = await repo.checkForUpdate();

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ParseError>());
    });
  });

  group('downloadApk', () {
    test('успех: zip распакован, SHA-256 совпал → Success(apk)', () async {
      final adapter = _DiskMockAdapter();
      final apkBytes =
          Uint8List.fromList(List.generate(1024, (i) => i % 256));
      final expectedHash = sha256.convert(apkBytes).toString();
      adapter.downloadBytes = _zipWithApk(apkBytes);
      final repo = _repo(adapter);
      final manifest = VersionManifest(
        versionCode: 5,
        versionName: '0.5.0',
        apkPath: 'releases/x.zip',
        releaseNotes: '',
        sha256: expectedHash,
        required: false,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(manifest, targetDir: tmpDir);

      expect(res, isA<Success>());
      final file = (res as Success).value as File;
      expect(await file.exists(), isTrue);
      expect(await file.length(), apkBytes.length);
      // zip после распаковки удалён.
      expect(await File('${tmpDir.path}/tsd_update.zip').exists(), isFalse);
      await tmpDir.delete(recursive: true);
    });

    test('успех: голый .apk (без zip), SHA-256 совпал → Success(apk)', () async {
      final adapter = _DiskMockAdapter();
      final apkBytes =
          Uint8List.fromList(List.generate(512, (i) => i % 256));
      final expectedHash = sha256.convert(apkBytes).toString();
      adapter.downloadBytes = apkBytes; // не запаковываем
      final repo = _repo(adapter);
      final manifest = VersionManifest(
        versionCode: 5,
        versionName: '0.5.0',
        apkPath: 'releases/tsd-inventory-0.5.0-5.apk',
        releaseNotes: '',
        sha256: expectedHash,
        required: false,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(manifest, targetDir: tmpDir);

      expect(res, isA<Success>());
      final file = (res as Success).value as File;
      expect(await file.exists(), isTrue);
      expect(await file.length(), apkBytes.length);
      // zip-файл не должен создаваться для голого apk.
      expect(await File('${tmpDir.path}/tsd_update.zip').exists(), isFalse);
      await tmpDir.delete(recursive: true);
    });

    test('скачивание без авторизации', () async {
      final adapter = _DiskMockAdapter(recordRequests: true);
      final apkBytes = Uint8List.fromList([1, 2, 3, 4]);
      adapter.downloadBytes = _zipWithApk(apkBytes);
      final repo = _repo(adapter);
      final manifest = VersionManifest(
        versionCode: 5,
        versionName: '0.5.0',
        apkPath: 'releases/x.zip',
        releaseNotes: '',
        sha256: sha256.convert(apkBytes).toString(),
        required: false,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      await repo.downloadApk(manifest, targetDir: tmpDir);

      for (final req in adapter.requests) {
        expect(req.headers['Authorization'], isNull);
      }
      await tmpDir.delete(recursive: true);
    });

    test('SHA-256 несовпадение → Failure(IntegrityError), apk удалён', () async {
      final adapter = _DiskMockAdapter();
      final apkBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      adapter.downloadBytes = _zipWithApk(apkBytes);
      final repo = _repo(adapter);
      final manifest = VersionManifest(
        versionCode: 5,
        versionName: '0.5.0',
        apkPath: 'releases/x.zip',
        releaseNotes: '',
        sha256: '0' * 64, // заведомо неверный хеш
        required: false,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(manifest, targetDir: tmpDir);

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<IntegrityError>());
      expect(await File('${tmpDir.path}/tsd_update.apk').exists(), isFalse);
      await tmpDir.delete(recursive: true);
    });

    test('пустой sha256 → Failure без скачивания', () async {
      final adapter = _DiskMockAdapter();
      final repo = _repo(adapter);
      final manifest = VersionManifest(
        versionCode: 5,
        versionName: '0.5.0',
        apkPath: 'releases/x.zip',
        releaseNotes: '',
        sha256: '',
        required: false,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(manifest, targetDir: tmpDir);

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ParseError>());
      // Ни resolve, ни скачивания не было.
      expect(adapter.requests, isEmpty);
      await tmpDir.delete(recursive: true);
    });

    test('пустой apkPath → Failure без скачивания', () async {
      final adapter = _DiskMockAdapter();
      final repo = _repo(adapter);
      final manifest = VersionManifest(
        versionCode: 5,
        versionName: '0.5.0',
        apkPath: '',
        releaseNotes: '',
        sha256: 'abc',
        required: false,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(manifest, targetDir: tmpDir);

      expect(res, isA<Failure>());
      expect(adapter.requests, isEmpty);
      await tmpDir.delete(recursive: true);
    });

    test('zip без .apk → Failure (распаковка не удалась)', () async {
      final adapter = _DiskMockAdapter();
      // Архив с файлом, не являющимся APK.
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 3, [1, 2, 3]));
      adapter.downloadBytes = ZipEncoder().encode(archive);
      final repo = _repo(adapter);
      final manifest = VersionManifest(
        versionCode: 5,
        versionName: '0.5.0',
        apkPath: 'releases/x.zip',
        releaseNotes: '',
        sha256: 'abc',
        required: false,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(manifest, targetDir: tmpDir);

      expect(res, isA<Failure>());
      await tmpDir.delete(recursive: true);
    });

    test('сеть недоступна при скачивании → Failure(NetworkError)', () async {
      final adapter = _DiskMockAdapter();
      adapter.downloadError = DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      );
      final repo = _repo(adapter);
      final manifest = VersionManifest(
        versionCode: 5,
        versionName: '0.5.0',
        apkPath: 'releases/x.zip',
        releaseNotes: '',
        sha256: 'abc',
        required: false,
      );
      final tmpDir = await Directory.systemTemp.createTemp('tsd_test_');

      final res = await repo.downloadApk(manifest, targetDir: tmpDir);

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
      await tmpDir.delete(recursive: true);
    });
  });
}
