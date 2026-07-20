/// Манифест версии: описание доступного обновления.
///
/// Контракт JSON (возвращается HTTP-сервисом 1С `/hs/inventory/update`,
/// который прозрачно ходит в Yandex Cloud и подставляет подписанную `apkUrl`):
/// ```json
/// {
///   "versionName": "0.2.6",
///   "versionCode": 8,
///   "apkUrl": "https://storage.yandexcloud.net/...?X-Amz-Signature=...",
///   "urlExpiresInSec": 600,
///   "sha256": "<sha256 APK в нижнем регистре>",
///   "releaseNotes": "Что нового",
///   "required": false
/// }
/// ```
///
/// В приватном бакете хранится `apkKey`, но мобильному приложению отдаётся уже
/// подписанная временная ссылка [apkUrl] (Cloud Function преобразует).
/// Сравнение версий идёт по целочисленному [versionCode] (монотонно растёт),
/// а не по строке versionName — это надёжнее и нечувствительно к формату X.Y.Z.
class VersionManifest {
  const VersionManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
    required this.sha256,
    required this.urlExpiresInSec,
    required this.required,
  });

  /// Целочисленный код версии (из pubspec: «0.2.6+8» → 8). Монотонно растёт.
  final int versionCode;

  /// Человекочитаемая версия («0.2.6»). Только для отображения.
  final String versionName;

  /// Подписанная временная ссылка на APK (Yandex Object Storage). При скачивании
  /// по ней НЕ нужна авторизация 1С, X-Update-Token или cookies — ссылка уже
  /// содержит подпись и действует [urlExpiresInSec] секунд.
  final String apkUrl;

  /// Текст изменений (необязательно). Показывается в диалоге.
  final String releaseNotes;

  /// SHA-256 APK в нижнем регистре. Обязателен для проверки целостности.
  /// Пустая строка → манифест невалиден, установку не запускаем.
  final String sha256;

  /// Срок действия [apkUrl] в секундах (от Cloud Function, обычно 600).
  /// Информационное поле; 0, если не прислан.
  final int urlExpiresInSec;

  /// Обязательное обновление: true → нельзя пропустить/закрыть диалог.
  final bool required;

  /// Достаточен ли манифест для установки: apkUrl и sha256 непусты.
  /// Без этого установку запускать нельзя.
  bool get isValid => apkUrl.isNotEmpty && sha256.isNotEmpty;

  /// Парсинг из JSON. Поля с невалидным типом заменяются значениями по
  /// умолчанию (versionCode/urlExpiresInSec → 0, строки → пустые, required →
  /// false), чтобы битый манифест не ронял приложение. Числа могут прийти
  /// числом или строкой («8»).
  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    return VersionManifest(
      versionCode: tryInt(json['versionCode']) ?? 0,
      versionName: (json['versionName'] ?? '').toString(),
      apkUrl: (json['apkUrl'] ?? '').toString(),
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
      sha256: (json['sha256'] ?? '').toString(),
      urlExpiresInSec: tryInt(json['urlExpiresInSec']) ?? 0,
      required: json['required'] == true,
    );
  }

  /// Доступно ли обновление: манифест новее текущей установленной версии.
  /// Сравнение строгое по versionCode (равные → не обновляемся).
  bool isNewerThan(int currentVersionCode) => versionCode > currentVersionCode;

  /// Безопасное приведение к int (1С/сервер может прислать «8» или 8).
  static int? tryInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
