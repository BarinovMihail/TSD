import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';

import '../domain/version_manifest.dart';

final _log = Logger('update_repository');

/// Колбэк прогресса скачивания APK: (полученоБайт, всегоБайт).
typedef DownloadProgress = void Function(int received, int total);

/// Получение манифеста версий и скачивание APK с портала internal.
///
/// Файлы категории APK (WPFD 3193) на портале **защищены**: плагин не отдаёт
/// прямых ссылок, а AJAX-эндпоинт `file.download` требует **cookies
/// авторизованной сессии WordPress** (Basic-auth WP не принимает). Поэтому
/// репозиторий сначала логинится на `wp-login.php` под service-учёткой
/// [AppConfig.portalCredentials], получает cookies и дальше качает манифест и
/// APK с ними. Учётка общая для всех ТСД (не 1С-учётка) — обновление идёт до входа.
///
/// Использует **отдельный [Dio]**, не [DioClient] 1С: адрес портала не связан
/// с базой 1С, свой таймаут, своя авторизация.
class UpdateRepository {
  UpdateRepository({
    Dio? dio,
    Future<String?> Function(Dio dio, Uri loginUrl, (String, String) creds)?
        login,
    (String, String)? credentials,
  })  : _dio = dio ?? Dio(),
        login = login ?? _wpLogin,
        credentials = credentials ?? AppConfig.portalCredentials;

  final Dio _dio;

  /// Функция cookie-логина на портал. По умолчанию [_wpLogin]; в тестах можно
  /// подсунуть заглушку, возвращающую фиксированную cookie.
  final Future<String?> Function(Dio dio, Uri loginUrl, (String, String) creds)
      login;

  /// Service-учётка портала (login, password).
  final (String, String) credentials;

  /// Кэш Cookie-заголовка сессии (один логин на серию запросов манифест+APK).
  String? _cookie;

  Future<String?> _ensureCookie() async {
    var c = _cookie;
    if (c != null && c.isNotEmpty) return c;
    try {
      c = await login(_dio, Uri.parse(AppConfig.portalLoginUrl), credentials);
      _cookie = c;
    } catch (e) {
      _log.warning('Cookie-логин на портал не удался: $e');
    }
    return c;
  }

  /// GET к манифесту версий → [VersionManifest]. null → нет данных/ошибка.
  /// Любая ошибка (сеть/парсинг) оборачивается в [Failure], не валит приложение.
  Future<Result<VersionManifest>> checkForUpdate(String manifestUrl) async {
    if (manifestUrl.isEmpty) {
      return const Failure(NetworkError());
    }
    try {
      final cookie = await _ensureCookie();
      final res = await _dio.get<dynamic>(
        manifestUrl,
        options: Options(headers: _portalHeaders(cookie), responseType: ResponseType.json),
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
      final cookie = await _ensureCookie();
      await _dio.download(
        apkUrl,
        file.path,
        onReceiveProgress: onProgress,
        options: Options(headers: _portalHeaders(cookie)),
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

  /// Заголовки для запросов к порталу: cookie сессии + Referer (WPFD проверяет).
  Map<String, dynamic> _portalHeaders(String? cookie) => {
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
        'Referer': '${AppConfig.portalUrl}/',
      };
}

/// Cookie-логин в WordPress: POST на [AppConfig.portalLoginUrl] с
/// `log`/`pwd` → собираем `Set-Cookie` в одну строку `name=value; ...`.
/// Возвращает null, если войти не удалось.
Future<String?> _wpLogin(
  Dio dio,
  Uri loginUrl,
  (String, String) creds,
) async {
  final form = FormData.fromMap({
    'log': creds.$1,
    'pwd': creds.$2,
    'wp-submit': 'Войти',
    'redirect_to': '${AppConfig.portalUrl}/wp-admin/',
    'testcookie': '1',
  });
  // followRedirects: false — не уходим на /wp-admin, нам нужны только cookies.
  final res = await dio.post(
    loginUrl.toString(),
    data: form,
    options: Options(
      followRedirects: false,
      validateStatus: (s) => s != null && s < 400,
      headers: {'Referer': '${AppConfig.portalUrl}/wp-login.php'},
    ),
  );
  final setCookies = res.headers['set-cookie'];
  if (setCookies == null || setCookies.isEmpty) return null;
  final pairs = <String>[];
  for (final raw in setCookies) {
    // raw: "name=value; Path=/; HttpOnly" → берём "name=value"
    final first = raw.split(';').first.trim();
    if (first.isNotEmpty) pairs.add(first);
  }
  final cookie = pairs.join('; ');
  if (!cookie.contains('wordpress_logged_in')) {
    _log.warning('WP-логин не дал wordpress_logged_in cookie — неверная учётка?');
    return null;
  }
  return cookie;
}
