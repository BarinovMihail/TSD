/// Манифест версии: описание доступного обновления.
///
/// Контракт JSON (файл `manifest.json` в публичной папке Яндекс Диска):
/// ```json
/// {
///   "versionName": "0.2.6",
///   "versionCode": 8,
///   "apkPath": "releases/tsd-inventory-0.2.6-8.zip",
///   "sha256": "<sha256 APK в нижнем регистре>",
///   "releaseNotes": "Что нового",
///   "required": false
/// }
/// ```
///
/// [apkPath] — путь к zip-архиву с APK относительно публичной папки Диска.
/// APK упакован в zip для выкладки; приложение скачивает архив и распаковывает
/// его перед установкой. SHA-256 считается по **распакованному** APK.
///
/// Временных подписанных ссылок больше нет: приложение при каждом скачивании
/// запрашивает у Диска свежую прямую ссылку через публичный эндпоинт
/// `/public/resources/download`.
///
/// Сравнение версий идёт по целочисленному [versionCode] (монотонно растёт),
/// а не по строке versionName — это надёжнее и нечувствительно к формату X.Y.Z.
class VersionManifest {
  const VersionManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkPath,
    required this.releaseNotes,
    required this.sha256,
    required this.required,
  });

  /// Целочисленный код версии (из pubspec: «0.2.6+8» → 8). Монотонно растёт.
  final int versionCode;

  /// Человекочитаемая версия («0.2.6»). Только для отображения.
  final String versionName;

  /// Путь к APK-файлу относительно публичной папки Диска. Поддерживаются два
  /// формата (определяется по расширению):
  /// - `.zip` — архив с APK (`releases/tsd-inventory-0.2.6-8.zip`), приложение
  ///   распаковывает;
  /// - `.apk` — готовый APK (`releases/tsd-inventory-0.2.6-8.apk`), берётся
  ///   как есть.
  ///
  /// Приложение само запросит по этому пути свежую временную ссылку на
  /// скачивание — отдельной авторизации не требуется, папка публичная.
  final String apkPath;

  /// Текст изменений (необязательно). Показывается в диалоге.
  final String releaseNotes;

  /// SHA-256 APK в нижнем регистре. Обязателен для проверки целостности.
  /// Пустая строка → манифест невалиден, установку не запускаем.
  /// Считается по **распакованному** из zip APK.
  final String sha256;

  /// Обязательное обновление: true → нельзя пропустить/закрыть диалог.
  final bool required;

  /// Достаточен ли манифест для установки: apkPath и sha256 непусты.
  /// Без этого установку запускать нельзя.
  bool get isValid => apkPath.isNotEmpty && sha256.isNotEmpty;

  /// Парсинг из JSON. Поля с невалидным типом заменяются значениями по
  /// умолчанию (versionCode → 0, строки → пустые, required → false), чтобы
  /// битый манифест не ронял приложение. Числа могут прийти числом или строкой
  /// («8»).
  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    return VersionManifest(
      versionCode: tryInt(json['versionCode']) ?? 0,
      versionName: (json['versionName'] ?? '').toString(),
      apkPath: (json['apkPath'] ?? '').toString(),
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
      sha256: (json['sha256'] ?? '').toString(),
      required: json['required'] == true,
    );
  }

  /// Доступно ли обновление: манифест новее текущей установленной версии.
  /// Сравнение строгое по versionCode (равные → не обновляемся).
  bool isNewerThan(int currentVersionCode) => versionCode > currentVersionCode;

  /// Безопасное приведение к int (сервер может прислать «8» или 8).
  static int? tryInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
