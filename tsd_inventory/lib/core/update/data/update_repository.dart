import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';

import '../domain/version_manifest.dart';

final _log = Logger('update_repository');

/// Колбэк прогресса скачивания APK: (полученоБайт, всегоБайт).
typedef DownloadProgress = void Function(int received, int total);

/// Получение манифеста версий и скачивание APK через защищённый сервис 1С.
///
/// Архитектура цепочки автообновления:
/// ```
/// приложение → 1С (HTTP-сервис /hs/inventory/update, Basic Auth)
///            → Yandex API Gateway → Cloud Function → приватный Object Storage.
/// ```
/// Приложение обращается **только** к 1С: тот же [DioClient] с Basic-аутентификацией
/// текущей сессии пользователя, таймаутами и failover по адресам ERP. Никаких
/// отдельных токенов, WordPress cookies или X-Update-Token в клиенте нет.
///
/// APK скачивается напрямую по подписанной ссылке [VersionManifest.apkUrl] из
/// ответа 1С — это временная ссылка Yandex Object Storage, уже содержащая
/// подпись, поэтому для неё используется **отдельный чистый [Dio]** без
/// авторизационных interceptor-ов (без Basic Auth 1С, без cookies, без токенов).
class UpdateRepository {
  UpdateRepository({required DioClient client, Dio? downloadDio})
    : _client = client,
      _downloadDio = downloadDio ?? Dio();

  /// Авторизованный клиент 1С: запрос манифеста идёт под Basic Auth сессии.
  final DioClient _client;

  /// Чистый Dio для скачивания APK по подписанной ссылке Object Storage.
  /// Намеренно без interceptor-ов: подписанная ссылка самодостаточна.
  final Dio _downloadDio;

  /// GET манифеста версий через защищённый endpoint 1С.
  /// [endpointUrl] — обычно `AppConfig.inventoryPath('update')`.
  /// Любая ошибка (сеть/парсинг/HTTP) оборачивается в [Failure], не валит
  /// приложение.
  Future<Result<VersionManifest>> checkForUpdate(String endpointUrl) async {
    if (endpointUrl.isEmpty) {
      return const Failure(NetworkError());
    }
    try {
      final res = await _client.getJson<dynamic>(endpointUrl);
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
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

  /// Скачивание APK и проверка целостности.
  ///
  /// [apkUrl] — подписанная ссылка Object Storage (без Basic Auth/cookies/токенов).
  /// [sha256] — ожидаемый хеш из манифеста; пустая строка → манифест невалиден,
  /// установка невозможна (возвращаем [ParseError], файл не качаем).
  /// [targetDir] — куда положить файл (по умолчанию временная директория системы;
  /// параметр нужен для тестов). [onProgress] — для прогресс-бара.
  ///
  /// После скачивания вычисляется SHA-256 файла и сравнивается с [sha256] без
  /// учёта регистра. При несовпадении файл удаляется и возвращается
  /// [IntegrityError] — установка не запускается.
  Future<Result<File>> downloadApk(
    String apkUrl, {
    required String sha256,
    Directory? targetDir,
    DownloadProgress? onProgress,
  }) async {
    if (apkUrl.isEmpty) {
      return const Failure(ParseError('Манифест версий некорректен'));
    }
    if (sha256.isEmpty) {
      // Без хеша целостность проверить нельзя — считаем манифест некорректным.
      return const Failure(ParseError('Манифест версий некорректен'));
    }
    try {
      final dir = targetDir ?? await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'tsd_update.apk'));
      await _downloadDio.download(
        apkUrl,
        file.path,
        onReceiveProgress: onProgress,
        // Никаких авторизационных заголовков: подписанная ссылка самодостаточна.
        deleteOnError: true,
      );
      // Обязательная проверка целостности до запуска установщика.
      final actual = await _sha256OfFile(file);
      if (actual.toLowerCase() != sha256.toLowerCase()) {
        _log.warning(
          'SHA-256 не совпал: expected=$sha256 actual=$actual; удаляю APK',
        );
        try {
          await file.delete();
        } catch (_) {
          /* файл мог уже удалиться через deleteOnError */
        }
        return const Failure(IntegrityError());
      }
      return Success(file);
    } on DioException catch (e) {
      _log.warning('Ошибка скачивания APK: $e');
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка сохранения APK: $e');
      return const Failure(NetworkError());
    }
  }

  /// SHA-256 файла в нижнем регистре (потоково, чтобы не грузить весь APK в память).
  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
