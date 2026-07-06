/// Манифест версии: описание доступного обновления с сервера.
///
/// Контракт JSON (см. план контроля версий):
/// ```json
/// {
///   "versionName": "0.2.0",
///   "versionCode": 2,
///   "apkUrl": "http://host/tsd/app-0.2.0.apk",
///   "releaseNotes": "Добавлен контроль версий"
/// }
/// ```
///
/// Сравнение версий идёт по целочисленному [versionCode] (монотонно растёт),
/// а не по строке versionName — это надёжнее и нечувствительно к формату X.Y.Z.
class VersionManifest {
  const VersionManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
  });

  /// Целочисленный код версии (из pubspec: «0.2.0+2» → 2). Монотонно растёт.
  final int versionCode;

  /// Человекочитаемая версия («0.2.0»). Только для отображения.
  final String versionName;

  /// URL скачивания APK. Может быть полным или относительно базы (см. AppConfig).
  final String apkUrl;

  /// Текст изменений (необязательно). Показывается в диалоге.
  final String releaseNotes;

  /// Парсинг из JSON. Поля с невалидным типом заменяются значениями по умолчанию
  /// (versionCode → 0, строки → пустые), чтобы битый манифест не ронял приложение.
  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    return VersionManifest(
      versionCode: tryVersionCode(json['versionCode']) ?? 0,
      versionName: (json['versionName'] ?? '').toString(),
      apkUrl: (json['apkUrl'] ?? '').toString(),
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
    );
  }

  /// Доступно ли обновление: манифест новее текущей установленной версии.
  /// Сравнение строгое по versionCode (равные → не обновляемся).
  bool isNewerThan(int currentVersionCode) => versionCode > currentVersionCode;

  /// Безопасное приведение versionCode к int.
  /// 1С/сервер может прислать число как строку («2») или как число (2).
  static int? tryVersionCode(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
