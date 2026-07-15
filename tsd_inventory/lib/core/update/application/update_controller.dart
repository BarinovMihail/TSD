import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/update/data/apk_installer.dart';
import 'package:tsd_inventory/core/update/data/update_repository.dart';
import 'package:tsd_inventory/core/update/domain/version_manifest.dart';

import '../../../features/auth/application/auth_controller.dart';

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
class UpdateController extends ChangeNotifier {
  UpdateController({
    required AppConfig config,
    required UpdateRepository repo,
    required ApkInstaller installer,
    Future<int> Function()? currentVersionCodeProvider,
  })  : _config = config,
        _repo = repo,
        _installer = installer,
        _currentVersionCodeProvider =
            currentVersionCodeProvider ?? _defaultVersionCode;

  final AppConfig _config;
  final UpdateRepository _repo;
  final ApkInstaller _installer;
  final Future<int> Function() _currentVersionCodeProvider;

  UpdateState state = const UpdateIdle();

  /// Доступно ли обновление прямо сейчас (для UI-интеграции).
  bool get hasUpdate => state is UpdateAvailable;

  /// Проверить наличие обновления. Если есть — состояние [UpdateAvailable].
  /// Манифест выключен (пустой URL) → тихо остаётся idle.
  Future<void> checkAndPrompt() async {
    if (_config.updateManifestUrl.isEmpty) return; // фича выключена
    state = const UpdateChecking();
    notifyListeners();

    final res = await _repo.checkForUpdate(_config.updateManifestUrl);
    final manifest = res.maybeWhen<VersionManifest?>(
      onValue: (m) => m,
      orElse: (_) => null,
    );
    if (manifest == null) {
      // Тихо глушим: проверка обновлений не должна мешать работе приложения.
      state = const UpdateIdle();
      notifyListeners();
      return;
    }
    final current = await _currentVersionCodeProvider();
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

    state = const UpdateDownloading(null);
    notifyListeners();

    final res = await _repo.downloadApk(manifest.resolvedApkUrl, onProgress: (r, t) {
      final p = t > 0 ? r / t : null;
      state = UpdateDownloading(p);
      notifyListeners();
    });
    final file = res.maybeWhen(
      onValue: (f) => f,
      orElse: (_) {
        state = const UpdateError('Не удалось скачать обновление');
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

  /// Сброс к idle (например, пользователь нажал «Пропустить»).
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

final updateControllerProvider =
    ChangeNotifierProvider<UpdateController>((ref) {
  final config = ref.watch(appConfigProvider);
  return UpdateController(
    config: config,
    repo: UpdateRepository(),
    installer: ApkInstaller(),
  );
});
