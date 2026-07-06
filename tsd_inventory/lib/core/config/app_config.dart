/// Конфигурация приложения: адрес 1С и режим сканера.
/// baseUrl настраивается (см. README): 10.0.2.2 для эмулятора, IP сервера для ТСД.
class AppConfig {
  const AppConfig({
    this.baseUrl = 'http://192.168.1.51/ERP_Local/',
    this.scannerMode = ScannerMode.keyboardWedge,
    this.connectTimeoutSec = 10,
    this.receiveTimeoutSec = 30,
    this.updateManifestUrl = '',
  });

  /// Базовый URL HTTP-сервисов 1С (без /hs/...).
  final String baseUrl;
  final ScannerMode scannerMode;
  final int connectTimeoutSec;
  final int receiveTimeoutSec;

  /// URL JSON-манифеста версий для автообновления.
  /// Пусто (по умолчанию) → фича выключена, проверка не идёт.
  /// Заполнить, когда определится хостинг (см. README «Контроль версий»).
  final String updateManifestUrl;

  /// Конструирует полный путь: baseUrl + '/hs/inventory/' + path.
  String inventoryPath(String path) {
    final base =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base/hs/inventory/$path';
  }
}

/// Режим приёма скан-кодов. По умолчанию keyboard wedge (M3 SDK недоступен).
enum ScannerMode { keyboardWedge, broadcastIntent, camera }
