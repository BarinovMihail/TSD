/// Конфигурация приложения: адрес 1С и режим сканера.
/// baseUrl настраивается (см. README): 10.0.2.2 для эмулятора, IP сервера для ТСД.
class AppConfig {
  const AppConfig({
    // По умолчанию — удалённая база ERP (db-srv14). См. [remoteUrl]/[localUrl].
    this.baseUrl = remoteUrl,
    this.scannerMode = ScannerMode.keyboardWedge,
    this.connectTimeoutSec = 10,
    this.receiveTimeoutSec = 30,
    // Манифест лежит на портале internal в папке APK (категория WPFD 3193).
    // См. README «Контроль версий» и [portalCredentials].
    this.updateManifestUrl = 'http://internal/wp-content/uploads/wpfd/3193/manifest.json',
  });

  /// Базовый URL HTTP-сервисов 1С (без /hs/...).
  final String baseUrl;

  /// Удалённая база ERP (db-srv14, основная). Сервис опубликован как `erp`
  /// (нижний регистр). Имя хоста db-srv14 — основной сетевой путь.
  static const remoteUrl = 'http://db-srv14/erp/';

  /// Резервный адрес той же базы ERP — по IP, на случай если hostname db-srv14
  /// не резолвится/недоступен со стороны ТСД. Переключение на него прозрачно
  /// происходит в [DioClient] только при сетевой ошибке/тайм-ауте.
  static const remoteUrlFallback = 'http://192.168.1.212/erp/';

  /// Все сетевые адреса базы ERP (основной + резервные) для failover в Dio.
  static const remoteHosts = [remoteUrl, remoteUrlFallback];

  /// Локальная база (fallback, если ERP недоступен целиком).
  static const localUrl = 'http://192.168.1.51/ERP_Local/';

  /// Базовый URL портала internal — корень, где лежит папка APK (WPFD 3193).
  static const portalUrl = 'http://internal';

  /// Папка APK на портале (категория WP File Download 3193): здесь физически
  /// лежат манифест и APK-файлы. Прямой URL скачивания = [portalApkDir] + имя.
  static const portalApkDir = '$portalUrl/wp-content/uploads/wpfd/3193/';

  /// Service-учётка для доступа к папке APK на портале internal.
  /// Прямые URL в /wp-content/uploads/wpfd/3193/ обычно публичны, но доступ
  /// к порталу/категории может требовать Basic-auth — поэтому [UpdateRepository]
  /// всегда прикладывает эти учётные данные к запросам манифеста и APK.
  static const portalCredentials = ('services', '92!OrSqCt9oRJ*K!cwHF0^yd');

  final ScannerMode scannerMode;
  final int connectTimeoutSec;
  final int receiveTimeoutSec;

  /// URL JSON-манифеста версий для автообновления.
  /// По умолчанию — manifest.json в папке APK на портале internal (WPFD 3193).
  /// Пусто → фича выключена. См. README «Контроль версий».
  final String updateManifestUrl;

  /// Конструирует полный путь: baseUrl + '/hs/inventory/' + path.
  String inventoryPath(String path) {
    final base =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base/hs/inventory/$path';
  }

  /// Короткий идентификатор базы для раздельного хранения учётных данных:
  /// `'erp'` для [remoteUrl], `'erp_local'` для [localUrl]. Пароли на базах
  /// могут отличаться, поэтому secure storage ключуется по этому суффиксу.
  static String keyForUrl(String baseUrl) {
    final path = baseUrl.toLowerCase();
    if (path.contains('erp_local')) return 'erp_local';
    return 'erp';
  }

  /// Текущая база конфига (для удобства).
  String get storageKey => keyForUrl(baseUrl);

  /// Принадлежит ли активный URL к семейству ERP (удалённая база).
  /// Используется [DioClient]-ом для failover по [remoteHosts]: переключаемся
  /// на резервный хост только при сетевой ошибке/тайм-ауте, не на HTTP-ответы
  /// (401/404/5xx — реальная проблема сервера, маскировать их нельзя).
  bool get isErpFamily => remoteHosts.any((h) => _sameHostAndPath(h, baseUrl));

  static bool _sameHostAndPath(String a, String b) {
    final la = a.toLowerCase().replaceAll(RegExp(r'/+$'), '');
    final lb = b.toLowerCase().replaceAll(RegExp(r'/+$'), '');
    return la == lb;
  }
}

/// Режим приёма скан-кодов. По умолчанию keyboard wedge (M3 SDK недоступен).
enum ScannerMode { keyboardWedge, broadcastIntent, camera }
