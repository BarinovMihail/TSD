/// Конфигурация источника автообновления на Яндекс Диске.
///
/// Приложение обращается к **публичным** эндпоинтам REST API Яндекс Диска,
/// которые не требуют OAuth-токена. Для этого корневая папка с обновлениями
/// (где лежат `manifest.json` и каталог `releases/`) должна быть опубликована
/// в Диске: «Поделиться» → «доступ по ссылке» (публичная). Публичная ссылка
/// имеет вид `https://disk.yandex.ru/d/XXXX` — именно её нужно подставить в
/// [YandexDiskUpdateConfig.publicKey].
///
/// APK инвентаризационного приложения не является секретом, поэтому публичный
/// доступ к папке безопасен. OAuth-токен используется **только** в скрипте
/// публикации (`scripts/publish-release.ps1`), но не в самом приложении.
class YandexDiskUpdateConfig {
  const YandexDiskUpdateConfig({
    required this.publicKey,
    required this.manifestPath,
    required this.apiBase,
  });

  /// Публичная ссылка на папку с обновлениями (`https://disk.yandex.ru/d/XXXX`).
  /// Используется как `public_key` во всех запросах к публичным ресурсам Диска.
  final String publicKey;

  /// Путь к манифесту версий относительно публичной папки (`manifest.json`).
  final String manifestPath;

  /// Базовый URL REST API Яндекс Диска
  /// (`https://cloud-api.yandex.net/v1/disk`).
  final String apiBase;
}

/// Источник обновлений по умолчанию: публичная папка Яндекс Диска `APK NO
/// DELETE/ТСД` (опубликована как «доступ по ссылке»).
const kYandexDiskUpdateConfig = YandexDiskUpdateConfig(
  publicKey: 'https://disk.yandex.ru/d/xJ70kJplsBCqlw',
  manifestPath: 'manifest.json',
  apiBase: 'https://cloud-api.yandex.net/v1/disk',
);
