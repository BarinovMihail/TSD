import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import '../config/app_config.dart';

final _log = Logger('dio_client');

/// Учётные данные Basic Auth.
class BasicCredentials {
  const BasicCredentials(this.login, this.password);
  final String login;
  final String password;

  String get headerValue =>
      'Basic ${base64Encode(utf8.encode('$login:$password'))}';
}

/// HttpClient на dio с BasicAuth + таймауты + failover по хостам.
///
/// Для базы ERP запросы идут по списку [AppConfig.remoteHosts] (основной
/// db-srv14 + резервный IP). При сетевой ошибке/тайм-ауте на текущем хосте
/// автоматически переключаемся на следующий и повторяем запрос. При любом
/// HTTP-ответе сервера (401/403/404/5xx) — НЕ переключаемся: это реальная
/// проблема учётки/публикации сервиса, маскировать её нельзя.
///
/// Рабочий хост запоминается ([_erpActiveHost]) и переиспользуется всеми
/// инстансами клиента в процессе — чтобы не ждать таймаут на мёртвом хосте
/// при каждом новом репозитории.
class DioClient {
  DioClient({
    required AppConfig config,
    required BasicCredentials credentials,
    Dio? dio,
  }) : _config = config {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: Duration(seconds: config.connectTimeoutSec),
            receiveTimeout: Duration(seconds: config.receiveTimeoutSec),
            responseType: ResponseType.json,
            headers: {'Accept': 'application/json'},
          ),
        );
    _dio.interceptors.add(_BasicAuthInterceptor(credentials));
  }

  final AppConfig _config;
  late final Dio _dio;

  /// Хосты для текущей базы. Для ERP — основной + резервный (failover),
  /// для ERP_Local — единственный.
  List<String> get _hosts =>
      _config.isErpFamily ? AppConfig.remoteHosts : [_config.baseUrl];

  Future<Response<T>> getJson<T>(String path, {Map<String, dynamic>? query}) =>
      _request<T>((url) => _dio.get<T>(url, queryParameters: query), path);

  /// POST с опциональным per-request receiveTimeout. Для тяжёлых операций 1С
  /// (например, генерация/запись нового штрихкода) передают большее значение,
  /// чтобы не получить ложный NetworkError по дефолтному таймауту.
  Future<Response<T>> postJson<T>(
    String path, {
    Object? body,
    Duration? receiveTimeout,
  }) => _request<T>(
    (url) => _dio.post<T>(
      url,
      data: body,
      options: receiveTimeout == null
          ? null
          : Options(receiveTimeout: receiveTimeout),
    ),
    path,
  );

  /// Выполняет запрос, перебирая хосты при сетевой ошибке/тайм-ауте.
  /// Стартуем с последнего успешного хоста ([_erpActiveHost] для ERP).
  Future<Response<T>> _request<T>(
    Future<Response<T>> Function(String url) call,
    String path,
  ) async {
    final hosts = _hosts;
    DioException? lastNetErr;
    // Для ERP начинаем с запомненного рабочего хоста; иначе с первого.
    final start = _config.isErpFamily ? _erpActiveHost : 0;
    for (var i = 0; i < hosts.length; i++) {
      final idx = (start + i) % hosts.length;
      final url = _join(hosts[idx], path);
      try {
        final resp = await call(url);
        if (_config.isErpFamily && _erpActiveHost != idx) {
          _erpActiveHost = idx;
          _log.info('Рабочий хост ERP: ${hosts[idx]}');
        }
        return resp;
      } on DioException catch (e) {
        if (_isSwitchable(e) && i < hosts.length - 1) {
          _log.warning(
            'Хост ${hosts[idx]} недоступен (${e.type}), пробую резервный',
          );
          lastNetErr = e;
          continue; // сетевая ошибка → следующий хост
        }
        rethrow; // HTTP-ответ (401/404/5xx) или последняя попытка → наверх
      }
    }
    throw lastNetErr!;
  }

  /// Ошибки, при которых имеет смысл переключиться на резервный хост:
  /// тайм-аут соединения/ответа и обрыв связи. HTTP-ответы (badResponse)
  /// и ошибку отмены сюда НЕ входят — их не маскируем.
  bool _isSwitchable(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError;

  /// Склейка baseUrl и пути: 'http://h/erp/' + 'hs/inventory/x' → полный URL.
  String _join(String baseUrl, String path) {
    final b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final p = path.startsWith('/') ? path.substring(1) : path;
    return '$b/$p';
  }

  /// Сброс запомненного рабочего хоста (например, при выходе/смене базы).
  static void resetActiveHost() => _erpActiveHost = 0;

  /// Индекс последнего успешного хоста ERP (общий для всех инстансов клиента).
  static int _erpActiveHost = 0;
}

/// Выставляет Authorization: Basic на каждый запрос.
class _BasicAuthInterceptor extends Interceptor {
  _BasicAuthInterceptor(this._creds);
  final BasicCredentials _creds;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = _creds.headerValue;
    handler.next(options);
  }
}
