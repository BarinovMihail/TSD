import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../application/update_controller.dart';
import '../domain/version_manifest.dart';

/// Диалог обновления: реагирует на [UpdateController.state].
///
/// Состояния UI:
/// - [UpdateAvailable] — «есть версия X.Y.Z» + заметки + «Обновить»
///   (и «Пропустить», только если обновление НЕ обязательное).
/// - [UpdateDownloading] — прогресс-бар + проценты.
/// - [UpdateInstalling] — «подтвердите установку».
/// - [UpdateError] — сообщение + «Повторить»/«Отмена» (отмена доступна только
///   для необязательного обновления).
///
/// При `manifest.required == true` диалог нельзя закрыть ни свайпом, ни вне окна,
/// и нет кнопки «Пропустить»: пользователь обязан обновиться. Чтобы не получить
/// бесконечный цикл диалогов, кнопка «Повторить» при ошибке запрашивает свежий
/// манифест (со свежей подписанной ссылкой) только по явному нажатию.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.controller});

  final UpdateController controller;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Обязательное обновление нельзя закрыть/пропустить — кроме случая, когда
  /// проверка уже не активна (UpdateError/UpdateIdle после сброса).
  bool get _required {
    final s = widget.controller.state;
    final m = s is UpdateAvailable ? s.manifest : _lastRequired;
    return m?.required ?? false;
  }

  VersionManifest? _lastRequired;

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    // Запоминаем обязательное обновление, чтобы сохранять поведение в
    // последующих состояниях (Downloading/Installing/Error).
    if (state is UpdateAvailable && state.manifest.required) {
      _lastRequired = state.manifest;
    } else if (state is UpdateIdle || state is UpdateChecking) {
      _lastRequired = null;
    }
    final inFlight = state is UpdateDownloading || state is UpdateInstalling;
    return PopScope(
      // Нельзя закрыть во время скачивания/установки и при обязательном обновлении.
      canPop: !inFlight && !_required,
      child: AlertDialog(
        title: _title(state),
        content: _content(state),
        actions: _actions(state),
      ),
    );
  }

  Widget _title(UpdateState state) {
    return Text(switch (state) {
      UpdateAvailable(:final manifest) => AppStrings.updateAvailableTitle(
        manifest.versionName,
      ),
      UpdateDownloading() => AppStrings.downloadingUpdate,
      UpdateInstalling() => AppStrings.downloadingUpdate,
      UpdateError(:final message) => message,
      _ => '',
    }, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700));
  }

  Widget _content(UpdateState state) {
    return switch (state) {
      UpdateAvailable(:final manifest) => Text(
        manifest.releaseNotes.isEmpty
            ? 'Обновите приложение, чтобы получить новую версию.'
            : manifest.releaseNotes,
        style: const TextStyle(fontSize: 18),
      ),
      UpdateDownloading(:final progress) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          if (progress != null)
            Text(
              AppStrings.updatePercent((progress * 100).round()),
              style: const TextStyle(fontSize: 18),
            ),
        ],
      ),
      UpdateInstalling() => Text(
        AppStrings.updateInstallingReady,
        style: const TextStyle(fontSize: 18),
      ),
      UpdateError() => const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
  }

  List<Widget> _actions(UpdateState state) {
    return switch (state) {
      UpdateAvailable(:final manifest) => [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => widget.controller.downloadAndInstall(),
              child: const Text(AppStrings.updateNow),
            ),
            // «Пропустить» — только для необязательного обновления.
            if (!manifest.required) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () {
                  widget.controller.skip();
                  Navigator.of(context).maybePop();
                },
                child: const Text(AppStrings.skipUpdate),
              ),
            ],
          ],
        ),
      ],
      UpdateError() => [
        Row(
          children: [
            // «Отмена» доступна только для необязательного обновления.
            if (!_required)
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    widget.controller.skip();
                    Navigator.of(context).maybePop();
                  },
                  child: const Text(AppStrings.cancel),
                ),
              ),
            if (!_required) const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                // Повторяем проверку: 1С выдаст свежий манифест со свежей
                // подписанной ссылкой. Цикла не возникает — только по нажатию.
                onPressed: () => widget.controller.checkAndPrompt(),
                child: const Text(AppStrings.retry),
              ),
            ),
          ],
        ),
      ],
      // Downloading / Installing: кнопок нет, ждём.
      _ => const [SizedBox.shrink()],
    };
  }
}
