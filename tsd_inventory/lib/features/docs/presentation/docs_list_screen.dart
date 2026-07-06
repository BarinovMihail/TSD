import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/presentation/confirm_dialog.dart';
import '../../../l10n/app_strings.dart';
import '../../auth/application/auth_controller.dart';
import '../../inventory/application/providers.dart';
import '../application/completed_docs_provider.dart';
import '../application/docs_controller.dart';
import '../domain/doc_list_item.dart';

class DocsListScreen extends ConsumerWidget {
  const DocsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      body: asyncDocs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: AppStrings.docsLoadError,
          onRetry: () => ref.read(docsControllerProvider.notifier).refresh(),
        ),
        data: (docs) {
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(AppStrings.docsEmpty,
                      style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(docsControllerProvider.notifier).refresh(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(docsControllerProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final completed = asyncCompleted.maybeWhen(
                      data: (s) => s.contains(docs[i].number),
                      orElse: () => false,
                    ) ||
                    docs[i].posted;
                return _DocCard(
                  doc: docs[i],
                  completed: completed,
                  onTap: () => context.go('/docs/${docs[i].number}'),
                  onUnmark: () => _confirmUnmark(context, ref, docs[i].number),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Long-press по отправленному документу → подтверждение → снять пометку.
  Future<void> _confirmUnmark(
      BuildContext context, WidgetRef ref, String number) async {
    await ConfirmDialog.show(
      context,
      title: const Text('Снять пометку «Отправлен»?'),
      content: Text.rich(TextSpan(children: [
        const TextSpan(text: 'Документ '),
        b(number),
        const TextSpan(text: ' снова будет показан как неотправленный.'),
      ])),
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
                    Text(doc.number,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(df.format(doc.date), style: const TextStyle(fontSize: 16)),
                    if (doc.department != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            '${AppStrings.deptLabel}: ${doc.department}',
                            style: TextStyle(fontSize: 14, color: scheme.outline)),
                      ),
                    if (completed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('✓ Отправлен',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: scheme.secondary)),
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
          ElevatedButton(onPressed: onRetry, child: const Text(AppStrings.retry)),
        ],
      ),
    );
  }
}
