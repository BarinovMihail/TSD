import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../application/update_controller.dart';

/// Диалог обновления: реагирует на [UpdateController.state].
///
/// Состояния UI:
/// - [UpdateAvailable] — «есть версия X.Y.Z» + заметки + «Обновить»/«Пропустить».
/// - [UpdateDownloading] — прогресс-бар + проценты.
/// - [UpdateInstalling] — «подтвердите установку».
/// - [UpdateError] — сообщение + «Повторить»/«Отмена».
///
/// Диалог нельзя закрыть свайпом во время скачивания/установки (barrierDismissible).
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

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    return PopScope(
      // Нельзя закрыть во время скачивания/установки.
      canPop: state is! UpdateDownloading && state is! UpdateInstalling,
      child: AlertDialog(
        title: _title(state),
        content: _content(state),
        actions: _actions(state),
      ),
    );
  }

  Widget _title(UpdateState state) {
    return Text(
      switch (state) {
        UpdateAvailable(:final manifest) =>
          AppStrings.updateAvailableTitle(manifest.versionName),
        UpdateDownloading() => AppStrings.downloadingUpdate,
        UpdateInstalling() => AppStrings.downloadingUpdate,
        UpdateError(:final message) => message,
        _ => '',
      },
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    );
  }

  Widget _content(UpdateState state) {
    return switch (state) {
      UpdateAvailable(:final manifest) => Text(
          manifest.releaseNotes.isEmpty
              ? 'Обновите приложение, чтобы получить новую версию.'
              : manifest.releaseNotes,
          style: const TextStyle(fontSize: 18)),
      UpdateDownloading(:final progress) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            if (progress != null)
              Text(AppStrings.updatePercent((progress * 100).round()),
                  style: const TextStyle(fontSize: 18)),
          ],
        ),
      UpdateInstalling() => Text(AppStrings.updateInstallingReady,
          style: const TextStyle(fontSize: 18)),
      UpdateError() => const SizedBox.shrink(),
      _ => const SizedBox.shrink(),
    };
  }

  List<Widget> _actions(UpdateState state) {
    return switch (state) {
      UpdateAvailable() => [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  textStyle: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () =>
                    widget.controller.downloadAndInstall(),
                child: const Text(AppStrings.updateNow),
              ),
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
          ),
        ],
      UpdateError() => [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text(AppStrings.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    widget.controller.skip();
                    widget.controller.checkAndPrompt();
                  },
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
