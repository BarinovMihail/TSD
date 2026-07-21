import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../application/update_controller.dart';
import '../domain/version_manifest.dart';
import 'update_dialog.dart';

/// Постоянная плашка для необязательного обновления.
///
/// Остаётся над списком документов и показывает весь цикл:
/// предложение обновить → скачивание → запуск установщика или
/// ошибку. Обязательные обновления здесь не показываются — для них
/// используется блокирующий [UpdateDialog].
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.controller,
    required this.manifest,
  });

  final UpdateController controller;
  final VersionManifest manifest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Material(
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.system_update_alt,
                  color: scheme.onSecondaryContainer,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(child: _content(state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _content(UpdateState state) {
    return switch (state) {
      UpdateDownloading(:final progress) => _ProgressContent(
        progress: progress,
      ),
      UpdateInstalling() => const _MessageContent(
        title: AppStrings.updateInstallingReady,
      ),
      UpdateChecking() => const _MessageContent(
        title: 'Проверка обновления…',
        showProgress: true,
      ),
      UpdateError(:final message) => _ErrorContent(
        message: message,
        onRetry: controller.downloadLatestAndInstall,
        onLater: controller.skip,
      ),
      _ => _AvailableContent(
        manifest: manifest,
        onUpdate: controller.downloadLatestAndInstall,
        onLater: controller.skip,
      ),
    };
  }
}

class _AvailableContent extends StatelessWidget {
  const _AvailableContent({
    required this.manifest,
    required this.onUpdate,
    required this.onLater,
  });

  final VersionManifest manifest;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.updateAvailableTitle(manifest.versionName),
          style: TextStyle(
            color: scheme.onSecondaryContainer,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (manifest.releaseNotes.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            manifest.releaseNotes,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              onPressed: onUpdate,
              icon: const Icon(Icons.download, size: 20),
              label: const Text(AppStrings.updateNow),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onLater,
              child: const Text(AppStrings.updateLater),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressContent extends StatelessWidget {
  const _ProgressContent({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.downloadingUpdate,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: progress),
        if (progress != null) ...[
          const SizedBox(height: 4),
          Text(AppStrings.updatePercent((progress! * 100).round())),
        ],
      ],
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.title, this.showProgress = false});

  final String title;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        if (showProgress) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({
    required this.message,
    required this.onRetry,
    required this.onLater,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: TextStyle(
            color: scheme.error,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              onPressed: onRetry,
              child: const Text(AppStrings.retry),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onLater,
              child: const Text(AppStrings.updateLater),
            ),
          ],
        ),
      ],
    );
  }
}
