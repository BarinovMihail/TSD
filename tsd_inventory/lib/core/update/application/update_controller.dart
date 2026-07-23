import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tsd_inventory/core/update/data/apk_installer.dart';
import 'package:tsd_inventory/core/update/data/update_repository.dart';
import 'package:tsd_inventory/core/update/data/yandex_disk_update_config.dart';
import 'package:tsd_inventory/core/update/domain/version_manifest.dart';

final _log = Logger('update_controller');

/// Состояние проверки обновлений.
sealed class UpdateState {
  const UpdateState();
}

/// Пусто: проверка ещё не шла / обновлений нет.
class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

/// Идёт запрос манифеста.
class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

/// Есть обновление. [manifest] — что доступно.
class UpdateAvailable extends UpdateState {
  final VersionManifest manifest;
  const UpdateAvailable(this.manifest);
}

/// Скачивание APK. [progress] 0.0..1.0 (или null, если длина неизвестна).
class UpdateDownloading extends UpdateState {
  final double? progress;
  const UpdateDownloading(this.progress);
}

/// APK скачан, системный установщик запущен.
class UpdateInstalling extends UpdateState {
  const UpdateInstalling();
}

/// Ошибка на любом этапе. [message] — для UI.
class UpdateError extends UpdateState {
  final String message;
  const UpdateError(this.message);
}

/// Контроллер контроля версий.
///
/// Жизненный цикл:
/// `checkAndPrompt()` → [UpdateChecking] → ([UpdateAvailable] | [UpdateIdle] |
/// [UpdateError]). При `UpdateAvailable` пользователь жмёт «Обновить» →
/// `downloadAndInstall()` → [UpdateDownloading] → [UpdateInstalling].
///
/// Манифест запрашивается из публичной папки Яндекс Диска через
/// [UpdateRepository] (без авторизации). Проверка запускается UI только после
/// успешного входа в 1С — провайдер читается на DocsListScreen.
/// Защита от повторных параллельных проверок — в [checkAndPrompt] (if not idle).
class UpdateController extends ChangeNotifier {
  UpdateController({
    required UpdateRepository repo,
    required ApkInstaller installer,
    Future<int> Function()? currentVersionCodeProvider,
  }) : _repo = repo,
       _installer = installer,
       _currentVersionCodeProvider =
           currentVersionCodeProvider ?? _defaultVersionCode;

  final UpdateRepository _repo;
  final ApkInstaller _installer;
  final Future<int> Function() _currentVersionCodeProvider;

  UpdateState state = const UpdateIdle();

  /// Доступно ли обновление прямо сейчас (для UI-интеграции).
  bool get hasUpdate => state is UpdateAvailable;

  /// Проверить наличие обновления. Если есть — состояние [UpdateAvailable].
  /// Не запускается повторно, пока проверка/обновление уже активны — это защита
  /// от двойного диалога при повторном входе на экран.
  Future<void> checkAndPrompt() async {
    if (state is UpdateChecking ||
        state is UpdateAvailable ||
        state is UpdateDownloading ||
        state is UpdateInstalling) {
      return;
    }
    state = const UpdateChecking();
    notifyListeners();

    // Манифест читается из публичной папки Яндекс Диска (см. UpdateRepository);
    // никаких путей/авторизации 1С больше не нужно.
    final res = await _repo.checkForUpdate();
    final manifest = res.maybeWhen<VersionManifest?>(
      onValue: (m) {
        _log.info(
          'Манифест получен: versionCode=${m.versionCode} '
          'versionName=${m.versionName} required=${m.required}',
        );
        return m;
      },
      orElse: (e) {
        _log.warning('Манифест не получен: ${e.userMessage}');
        return null;
      },
    );
    if (manifest == null) {
      // Тихо глушим: проверка обновлений не должна мешать работе приложения.
      state = const UpdateIdle();
      notifyListeners();
      return;
    }
    final current = await _currentVersionCodeProvider();
    _log.info(
      'Сравнение версий: manifest=${manifest.versionCode} current=$current',
    );
    state = manifest.isNewerThan(current)
        ? UpdateAvailable(manifest)
        : const UpdateIdle();
    notifyListeners();
  }

  /// Скачать APK и запустить системный установщик.
  Future<void> downloadAndInstall() async {
    final s = state;
    if (s is! UpdateAvailable) return;
    final manifest = s.manifest;

    // Нет apkPath или хеша → установить нельзя.
    if (!manifest.isValid) {
      state = const UpdateError('Манифест обновления некорректен');
      notifyListeners();
      return;
    }

    state = const UpdateDownloading(null);
    notifyListeners();

    final res = await _repo.downloadApk(
      manifest,
      onProgress: (r, t) {
        final p = t > 0 ? r / t : null;
        state = UpdateDownloading(p);
        notifyListeners();
      },
    );
    final file = res.maybeWhen(
      onValue: (f) => f,
      orElse: (e) {
        state = UpdateError(e.userMessage);
        notifyListeners();
      },
    );
    if (file == null) return;

    try {
      state = const UpdateInstalling();
      notifyListeners();
      await _installer.installApk(file);
      // После запуска установщика UI остаётся в UpdateInstalling — оператор
      // подтверждает установку в системном диалоге. Сюда вернёмся уже новой
      // версией после перезапуска.
    } catch (e) {
      state = UpdateError('Не удалось запустить установку: $e');
      notifyListeners();
    }
  }

  /// Повторно запросить манифест и сразу начать установку.
  ///
  /// Плашка может оставаться на экране долго. Поэтому перед скачиванием всегда
  /// получаем свежий манифест и ещё раз проверяем, что версия новее. Временные
  /// ссылки на скачивание Яндекс Диск выдаёт при каждом запросе файла, поэтому
  /// проблем с «протуханием» быть не может.
  Future<void> downloadLatestAndInstall() async {
    if (state is! UpdateAvailable && state is! UpdateError) return;

    state = const UpdateChecking();
    notifyListeners();

    final res = await _repo.checkForUpdate();
    String? errorMessage;
    final manifest = res.maybeWhen<VersionManifest?>(
      onValue: (value) => value,
      orElse: (value) {
        errorMessage = value.userMessage;
        return null;
      },
    );
    if (manifest == null) {
      state = UpdateError(
        errorMessage ?? 'Не удалось получить обновление',
      );
      notifyListeners();
      return;
    }

    final current = await _currentVersionCodeProvider();
    if (!manifest.isNewerThan(current)) {
      state = const UpdateIdle();
      notifyListeners();
      return;
    }

    state = UpdateAvailable(manifest);
    notifyListeners();
    await downloadAndInstall();
  }

  /// Сброс к idle (например, пользователь нажал «Пропустить»). Доступен только
  /// для необязательных обновлений — UI прячет кнопку при `manifest.required`.
  void skip() {
    state = const UpdateIdle();
    notifyListeners();
  }

  /// Получение своего versionCode через package_info_plus.
  static Future<int> _defaultVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }
}

final updateControllerProvider = ChangeNotifierProvider<UpdateController>((ref) {
  // Источник обновлений — публичная папка Яндекс Диска, авторизация не нужна.
  // Защиту «только после входа в 1С» обеспечивает экран DocsListScreen:
  // провайдер читается именно там (после успешной авторизации).
  return UpdateController(
    repo: UpdateRepository(config: kYandexDiskUpdateConfig),
    installer: ApkInstaller(),
  );
});
