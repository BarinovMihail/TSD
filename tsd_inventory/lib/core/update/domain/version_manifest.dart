import 'package:tsd_inventory/core/config/app_config.dart';

/// Манифест версии: описание доступного обновления с сервера.
///
/// Контракт JSON:
/// ```json
/// {
///   "versionName": "0.2.5",
///   "versionCode": 7,
///   "apkFileId": 58930,
///   "releaseNotes": "Что нового"
/// }
/// ```
///
/// `apkFileId` — это **ID файла APK в категории WP File Download** на портале
/// internal (категория 3193). Прямых ссылок плагин не отдаёт (файлы защищены),
/// поэтому приложение скачивает APK через AJAX-эндпоинт `file.download` под
/// cookie-сессией. ID файла виден в админке WPFD при заливке APK; его вписывают
/// в манифест при публикации новой версии.
///
/// Сравнение версий идёт по целочисленному [versionCode] (монотонно растёт),
/// а не по строке versionName — это надёжнее и нечувствительно к формату X.Y.Z.
class VersionManifest {
  const VersionManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkFileId,
    required this.releaseNotes,
  });

  /// Целочисленный код версии (из pubspec: «0.2.5+7» → 7). Монотонно растёт.
  final int versionCode;

  /// Человекочитаемая версия («0.2.5»). Только для отображения.
  final String versionName;

  /// ID файла APK в категории WPFD на портале. См. описание класса.
  final int apkFileId;

  /// Текст изменений (необязательно). Показывается в диалоге.
  final String releaseNotes;

  /// Полный URL скачивания APK через эндпоинт плагина (подставляется [apkFileId]).
  /// Запрос требует cookies авторизованной сессии WP (см. [UpdateRepository]).
  String get resolvedApkUrl => AppConfig.portalFileDownloadUrl(apkFileId);

  /// Парсинг из JSON. Поля с невалидным типом заменяются значениями по умолчанию
  /// (versionCode/apkFileId → 0, строки → пустые), чтобы битый манифест не ронял
  /// приложение. apkFileId может прийти числом или строкой («58930»).
  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    return VersionManifest(
      versionCode: tryInt(json['versionCode']) ?? 0,
      versionName: (json['versionName'] ?? '').toString(),
      apkFileId: tryInt(json['apkFileId']) ?? 0,
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
    );
  }

  /// Доступно ли обновление: манифест новее текущей установленной версии.
  /// Сравнение строгое по versionCode (равные → не обновляемся).
  bool isNewerThan(int currentVersionCode) => versionCode > currentVersionCode;

  /// Безопасное приведение к int (1С/сервер может прислать «58930» или 58930).
  static int? tryInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
