import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/presentation/confirm_dialog.dart';
import '../../../core/update/application/update_controller.dart';
import '../../../core/update/domain/version_manifest.dart';
import '../../../core/update/presentation/update_banner.dart';
import '../../../core/update/presentation/update_dialog.dart';
import '../../../l10n/app_strings.dart';
import '../../auth/application/auth_controller.dart';
import '../../inventory/application/providers.dart';
import '../application/completed_docs_provider.dart';
import '../application/docs_controller.dart';
import '../domain/doc_list_item.dart';
import '../domain/docs_list_filter.dart';

class DocsListScreen extends ConsumerStatefulWidget {
  const DocsListScreen({super.key});

  @override
  ConsumerState<DocsListScreen> createState() => _DocsListScreenState();
}

class _DocsListScreenState extends ConsumerState<DocsListScreen>
    with WidgetsBindingObserver {
  static const _updateCheckInterval = Duration(minutes: 10);

  final _searchController = TextEditingController();
  String _searchQuery = '';
  DocsSortOrder _sortOrder = DocsSortOrder.newestFirst;

  /// Обязательное обновление показывается диалогом только один раз.
  bool _requiredUpdateDialogShown = false;

  /// Необязательное обновление остаётся в плашке во время
  /// скачивания/установки, когда state уже не UpdateAvailable.
  VersionManifest? _optionalUpdateManifest;

  DateTime? _lastUpdateCheckAt;

  /// Ссылка на контроллер обновлений: сохраняем при запуске проверки, чтобы
  /// безопасно снять слушателя в dispose (к моменту dispose сессия может уже
  /// быть сброшена logout-ом, и ref.read(updateControllerProvider) выбросит
  /// StateError — провайдер требует сессии).
  UpdateController? _updateController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Проверка обновлений — после успешной авторизации (сессия уже есть),
    // endpoint 1С /hs/inventory/update защищён Basic-аутентификацией.
    // Post-frame, чтобы showDialog шёл от построенного контекста экрана.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkForUpdates(force: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkForUpdates());
    }
  }

  void _onUpdateStateChanged() {
    final controller = _updateController;
    if (controller == null || !mounted) return;
    final state = controller.state;
    if (state case UpdateAvailable(:final manifest)) {
      if (!manifest.required) {
        if (_optionalUpdateManifest?.versionCode != manifest.versionCode) {
          setState(() => _optionalUpdateManifest = manifest);
        }
        return;
      }

      if (_optionalUpdateManifest != null) {
        setState(() => _optionalUpdateManifest = null);
      }
      if (_requiredUpdateDialogShown) return;
      _requiredUpdateDialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(controller: controller),
      ).then((_) {
        if (mounted) controller.removeListener(_onUpdateStateChanged);
      });
    } else if (state is UpdateIdle && _optionalUpdateManifest != null) {
      setState(() => _optionalUpdateManifest = null);
    }
  }

  Future<void> _checkForUpdates({bool force = false}) async {
    if (!mounted) return;
    final now = DateTime.now();
    final previousCheck = _lastUpdateCheckAt;
    if (!force &&
        previousCheck != null &&
        now.difference(previousCheck) < _updateCheckInterval) {
      return;
    }
    _lastUpdateCheckAt = now;
    try {
      final controller = ref.read(updateControllerProvider);
      _updateController = controller;
      controller.removeListener(_onUpdateStateChanged);
      controller.addListener(_onUpdateStateChanged);
      await controller.checkAndPrompt();
    } catch (e) {
      // Случиться не должно (провайдер требует сессии, а мы уже на docs-экране),
      // но ошибка проверки обновления никогда не должна мешать работе.
      debugPrint('Проверка обновления не запустилась: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Слушатель обновлений мог остаться, если диалог не был показан. Контроллер
    // dispose-ится самим Riverpod при исчезновении зависимостей — снятие
    // слушателя с уже disposed ChangeNotifier безопасно (Flutter не бросает).
    _updateController?.removeListener(_onUpdateStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fio = ref.watch(authControllerProvider).session?.fio ?? '';
    final asyncDocs = ref.watch(docsControllerProvider);
    final asyncCompleted = ref.watch(completedDocsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fio, style: const TextStyle(fontSize: 18)),
            const Text(AppStrings.docsTitle, style: TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_optionalUpdateManifest != null && _updateController != null)
            UpdateBanner(
              controller: _updateController!,
              manifest: _optionalUpdateManifest!,
            ),
          Expanded(
            child: asyncDocs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                message: AppStrings.docsLoadError,
                onRetry: () =>
                    ref.read(docsControllerProvider.notifier).refresh(),
              ),
              data: (docs) {
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          AppStrings.docsEmpty,
                          style: TextStyle(fontSize: 20),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => ref
                              .read(docsControllerProvider.notifier)
                              .refresh(),
                          child: const Text(AppStrings.retry),
                        ),
                      ],
                    ),
                  );
                }
                final visibleDocs = filterAndSortDocs(
                  docs,
                  query: _searchQuery,
                  sortOrder: _sortOrder,
                );
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: AppStrings.searchDocument,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: AppStrings.clearSearch,
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text(AppStrings.newestFirst),
                              selected:
                                  _sortOrder == DocsSortOrder.newestFirst,
                              onSelected: (_) => setState(
                                () => _sortOrder = DocsSortOrder.newestFirst,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text(AppStrings.oldestFirst),
                              selected:
                                  _sortOrder == DocsSortOrder.oldestFirst,
                              onSelected: (_) => setState(
                                () => _sortOrder = DocsSortOrder.oldestFirst,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshDocsAndUpdates,
                        child: visibleDocs.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 96),
                                  Center(
                                    child: Text(
                                      AppStrings.docsSearchEmpty,
                                      style: TextStyle(fontSize: 18),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                itemCount: visibleDocs.length,
                                itemBuilder: (context, i) {
                                  final doc = visibleDocs[i];
                                  final completed =
                                      asyncCompleted.maybeWhen(
                                        data: (s) => s.contains(doc.number),
                                        orElse: () => false,
                                      ) ||
                                      doc.posted;
                                  return _DocCard(
                                    doc: doc,
                                    completed: completed,
                                    onTap: () =>
                                        context.go('/docs/${doc.number}'),
                                    onUnmark: () => _confirmUnmark(
                                      context,
                                      ref,
                                      doc.number,
                                    ),
                                  );
                                },
                              ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshDocsAndUpdates() async {
    await Future.wait([
      ref.read(docsControllerProvider.notifier).refresh(),
      _checkForUpdates(force: true),
    ]);
  }

  /// Long-press по отправленному документу → подтверждение → снять пометку.
  Future<void> _confirmUnmark(
    BuildContext context,
    WidgetRef ref,
    String number,
  ) async {
    await ConfirmDialog.show(
      context,
      title: const Text('Снять пометку «Отправлен»?'),
      content: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Документ '),
            b(number),
            const TextSpan(text: ' снова будет показан как неотправленный.'),
          ],
        ),
      ),
      // Безопасное действие — отмена (заполненная, сверху).
      primaryLabel: AppStrings.cancel,
      onPrimary: () {},
      // Рискованное действие — снять пометку (outline, снизу, красная).
      secondaryLabel: 'Снять пометку',
      onSecondary: () async {
        final db = ref.read(appDatabaseProvider);
        await db.unmarkDocCompleted(number);
        ref.invalidate(completedDocsProvider);
      },
      destructiveSecondary: true,
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.doc,
    required this.completed,
    required this.onTap,
    this.onUnmark,
  });
  final DocListItem doc;
  final bool completed; // документ полностью отправлен в 1С
  final VoidCallback onTap;
  // Long-press на отправленном документе → снять пометку. null, если не отправлен.
  final VoidCallback? onUnmark;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: completed ? onUnmark : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Метка «отправлен» — иконка слева.
              Icon(
                completed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: completed ? scheme.secondary : scheme.outline,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.number,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      df.format(doc.date),
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (doc.department != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${AppStrings.deptLabel}: ${doc.department}',
                          style: TextStyle(fontSize: 14, color: scheme.outline),
                        ),
                      ),
                    if (completed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '✓ Отправлен',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: scheme.secondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 56, color: scheme.error),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text(AppStrings.retry),
          ),
        ],
      ),
    );
  }
}
