import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';

import '../data/yandex_disk_update_config.dart';
import '../domain/version_manifest.dart';

final _log = Logger('update_repository');

/// Колбэк прогресса скачивания: (полученоБайт, всегоБайт).
typedef DownloadProgress = void Function(int received, int total);

/// Получение манифеста версий и скачивание APK из публичной папки Яндекс Диска.
///
/// Архитектура цепочки автообновления:
/// ```
/// приложение → REST API Яндекс Диска (публичные эндпоинты, без токена)
///   GET /public/resources/download?public_key=...&path=... → временная прямая
///   ссылка (href) → скачивание файла.
/// ```
/// Папка с обновлениями публикуется в Диске вручную (см.
/// [YandexDiskUpdateConfig]); приложение ходит в неё как в публичный ресурс.
/// Никаких учётных данных 1С, OAuth-токенов или `X-Update-Token` в клиенте нет.
///
/// APK хранится на Диске zip-архивом (см. [VersionManifest.apkPath]); репозиторий
/// скачивает архив, **распаковывает** его и проверяет SHA-256 извлечённого APK.
class UpdateRepository {
  UpdateRepository({
    required YandexDiskUpdateConfig config,
    Dio? dio,
  }) : _config = config,
       _dio = dio ?? Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 60),
           responseType: ResponseType.json,
           headers: {'Accept': 'application/json'},
         ),
       );

  /// Конфиг публичной папки Диска.
  final YandexDiskUpdateConfig _config;

  /// Единый чистый Dio: и для запросов к API Диска, и для скачивания файлов по
  /// выданным href. Папка публичная — авторизационных заголовков не требуется.
  final Dio _dio;

  /// GET манифеста версий из публичной папки Диска.
  ///
  /// Двухшаговая схема:
  /// 1. `GET /public/resources/download?public_key=...&path=manifest.json`
  ///    → JSON с временной прямой ссылкой `href` и сроком её действия.
  /// 2. Скачивание `manifest.json` по `href` и парсинг в [VersionManifest].
  ///
  /// Любая ошибка (сеть/парсинг/HTTP) оборачивается в [Failure], не валит
  /// приложение.
  Future<Result<VersionManifest>> checkForUpdate() async {
    try {
      final href = await _resolveDownloadHref(_config.manifestPath);
      final bytes = await _downloadBytes(href);
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) {
        _log.warning('Манифест не является JSON-объектом: $data');
        return const Failure(ParseError('Манифест версий некорректен'));
      }
      return Success(VersionManifest.fromJson(data));
    } on DioException catch (e) {
      _log.warning('Ошибка запроса манифеста: $e');
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка разбора манифеста: $e');
      return const Failure(ParseError('Манифест версий некорректен'));
    }
  }

  /// Скачать zip с APK, распаковать и проверить целостность.
  ///
  /// [manifest.apkPath] — путь к zip-архиву внутри публичной папки Диска.
  /// [manifest.sha256] — ожидаемый хеш **извлечённого** APK; пустая строка →
  /// манифест невалиден, установка невозможна (возвращаем [ParseError], файл не
  /// качаем). [targetDir] — куда положить APK (по умолчанию временная
  /// директория системы; параметр нужен для тестов). [onProgress] — прогресс-бар.
  ///
  /// Двухшаговое скачивание (как в [checkForUpdate]): сначала свежий href для
  /// [VersionManifest.apkPath], затем сам zip. После распаковки берём единственный
  /// файл `.apk` из архива, считаем SHA-256 и сравниваем с манифестом без учёта
  /// регистра. При несовпадении файлы удаляются и возвращается [IntegrityError]
  /// — установка не запускается.
  Future<Result<File>> downloadApk(
    VersionManifest manifest, {
    Directory? targetDir,
    DownloadProgress? onProgress,
  }) async {
    if (!manifest.isValid) {
      return const Failure(ParseError('Манифест версий некорректен'));
    }
    try {
      final dir = targetDir ?? await getTemporaryDirectory();
      final href = await _resolveDownloadHref(manifest.apkPath);
      final zipFile = File(p.join(dir.path, 'tsd_update.zip'));
      await _dio.download(
        href,
        zipFile.path,
        onReceiveProgress: onProgress,
        deleteOnError: true,
      );
      // Распаковываем архив, извлекаем единственный .apk.
      final apkFile = await _extractApk(zipFile, dir);
      // Обязательная проверка целостности до запуска установщика.
      final actual = await _sha256OfFile(apkFile);
      if (actual.toLowerCase() != manifest.sha256.toLowerCase()) {
        _log.warning(
          'SHA-256 не совпал: expected=${manifest.sha256} actual=$actual; '
          'удаляю APK и zip',
        );
        await _tryDelete(zipFile);
        await _tryDelete(apkFile);
        return const Failure(IntegrityError());
      }
      return Success(apkFile);
    } on DioException catch (e) {
      _log.warning('Ошибка скачивания APK: $e');
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка сохранения/распаковки APK: $e');
      return const Failure(NetworkError());
    }
  }

  /// Запрос временной прямой ссылки на файл [path] внутри публичной папки Диска.
  ///
  /// Эндпоинт `GET /public/resources/download` возвращает JSON вида
  /// `{ "href": "https://...", "method": "GET", "templated": false }`. Берём
  /// `href` — по нему файл (манифест или zip) скачивается без авторизации.
  ///
  /// Важно: для **публичных** ресурсов Диск требует путь относительно корня
  /// публичной папки **с ведущим `/`** (`/manifest.json`, `/releases/x.zip`).
  /// Здесь гарантированно добавляем `/`, чтобы можно было хранить пути в
  /// конфиге/манифесте без слэша (`manifest.json`, `releases/x.zip`).
  Future<String> _resolveDownloadHref(String path) async {
    final normalized = path.startsWith('/') ? path : '/$path';
    final res = await _dio.get<dynamic>(
      '${_config.apiBase}/public/resources/download',
      queryParameters: {'public_key': _config.publicKey, 'path': normalized},
    );
    final data = res.data is String
        ? jsonDecode(res.data as String)
        : res.data;
    if (data is! Map) {
      throw const ParseError('Некорректный ответ Диска (download)');
    }
    final href = data['href'];
    if (href is! String || href.isEmpty) {
      throw const ParseError('Некорректный ответ Диска (download)');
    }
    return href;
  }

  /// Скачивание байтов по [href] (для манифеста — небольшой файл).
  Future<List<int>> _downloadBytes(String href) async {
    final res = await _dio.get<List<int>>(
      href,
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }

  /// Распаковка zip → извлечение единственного файла `.apk` в [dir].
  ///
  /// Архив содержит один `.apk` (возможно внутри каталога). Если `.apk` нет или
  /// их несколько — кидаем исключение (ловится в [downloadApk] → NetworkError).
  /// Zip-файл после распаковки удаляем.
  Future<File> _extractApk(File zipFile, Directory dir) async {
    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    ArchiveFile? apk;
    for (final f in archive) {
      if (f.name.toLowerCase().endsWith('.apk')) {
        if (apk != null) {
          throw const ParseError('В архиве более одного APK');
        }
        apk = f;
      }
    }
    if (apk == null) {
      throw const ParseError('В архиве нет APK');
    }
    final apkFile = File(p.join(dir.path, 'tsd_update.apk'));
    // isBinary == false трактуется как текст — пишем байты как есть для любого
    // содержимого (APK всегда бинарный, archive помечает его isBinary=true).
    await apkFile.writeAsBytes(apk.content as List<int>, flush: true);
    await _tryDelete(zipFile);
    return apkFile;
  }

  /// SHA-256 файла в нижнем регистре (потоково, чтобы не грузить весь APK в память).
  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Удаление файла, игнорируя ошибку (файл мог уже удалиться через deleteOnError).
  static Future<void> _tryDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      /* лучший esfuerzo: файл мог быть уже удалён */
    }
  }
}
