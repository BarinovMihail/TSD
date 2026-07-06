import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';

import '../domain/version_manifest.dart';

final _log = Logger('update_repository');

/// Колбэк прогресса скачивания APK: (полученоБайт, всегоБайт).
typedef DownloadProgress = void Function(int received, int total);

/// Получение манифеста версий и скачивание APK.
///
/// Использует **отдельный [Dio]** без Basic-авторизации: проверка обновлений
/// идёт до входа пользователя в приложение, учётки 1С ещё нет. Сервер обновлений
/// (когда будет настроен) не должен требовать 1С-учётку.
class UpdateRepository {
  UpdateRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// GET к манифесту версий → [VersionManifest]. null → нет данных/ошибка.
  /// Любая ошибка (сеть/парсинг) оборачивается в [Failure], не валит приложение.
  Future<Result<VersionManifest>> checkForUpdate(String manifestUrl) async {
    if (manifestUrl.isEmpty) {
      return const Failure(NetworkError());
    }
    try {
      final res = await _dio.get<dynamic>(manifestUrl);
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
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

  /// Скачивание APK. [targetDir] — куда положить файл (по умолчанию
  /// временная директория системы; параметр нужен для тестов). Возвращает файл.
  /// [onProgress] вызывается по мере загрузки (для прогресс-бара).
  Future<Result<File>> downloadApk(
    String apkUrl, {
    Directory? targetDir,
    DownloadProgress? onProgress,
  }) async {
    try {
      final dir = targetDir ?? await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'tsd_update.apk'));
      await _dio.download(
        apkUrl,
        file.path,
        onReceiveProgress: onProgress,
      );
      return Success(file);
    } on DioException catch (e) {
      _log.warning('Ошибка скачивания APK: $e');
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка сохранения APK: $e');
      return const Failure(NetworkError());
    }
  }
}
