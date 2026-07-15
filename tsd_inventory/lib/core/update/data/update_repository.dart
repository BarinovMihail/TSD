import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';

import '../domain/version_manifest.dart';

final _log = Logger('update_repository');

/// Колбэк прогресса скачивания APK: (полученоБайт, всегоБайт).
typedef DownloadProgress = void Function(int received, int total);

/// Получение манифеста версий и скачивание APK с портала internal.
///
/// Манифест и APK лежат в папке APK (WPFD-категория 3193) на портале.
/// Доступ к порталу требует service-учётки [AppConfig.portalCredentials],
/// поэтому к каждому запросу прикладывается Basic Auth. Учётка общая для
/// всех ТСД (не 1С-учётка пользователя) — проверка обновлений идёт до входа.
///
/// Использует **отдельный [Dio]**, не [DioClient] 1С: адрес портала не связан
/// с базой 1С, свой таймаут/ретраи.
class UpdateRepository {
  UpdateRepository({Dio? dio, BasicCredentials? portalCredentials})
      : _dio = dio ?? Dio(),
        _creds = portalCredentials ??
            BasicCredentials(
              AppConfig.portalCredentials.$1,
              AppConfig.portalCredentials.$2,
            );

  final Dio _dio;
  final BasicCredentials _creds;

  /// GET к манифесту версий → [VersionManifest]. null → нет данных/ошибка.
  /// Любая ошибка (сеть/парсинг) оборачивается в [Failure], не валит приложение.
  Future<Result<VersionManifest>> checkForUpdate(String manifestUrl) async {
    if (manifestUrl.isEmpty) {
      return const Failure(NetworkError());
    }
    try {
      final res = await _dio.get<dynamic>(
        manifestUrl,
        options: _portalOptions(),
      );
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
        options: _portalOptions(),
        deleteOnError: true,
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

  /// Опции с Basic Auth портала для запросов манифеста/APK.
  Options _portalOptions() => Options(headers: {
        'Authorization': _creds.headerValue,
      });
}
