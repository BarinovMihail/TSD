import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_strings.dart';
import '../../auth/application/auth_controller.dart';
import '../application/docs_controller.dart';
import '../domain/doc_list_item.dart';

class DocsListScreen extends ConsumerWidget {
  const DocsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fio = ref.watch(authControllerProvider).session?.fio ?? '';
    final asyncDocs = ref.watch(docsControllerProvider);

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
              itemBuilder: (context, i) => _DocCard(
                doc: docs[i],
                onTap: () => context.go('/docs/${docs[i].number}'),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, required this.onTap});
  final DocListItem doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.number,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(df.format(doc.date), style: const TextStyle(fontSize: 16)),
                    if (doc.departmentGuid != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            '${AppStrings.deptLabel}: ${doc.departmentGuid}',
                            style: TextStyle(fontSize: 14, color: scheme.outline)),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: doc.posted
                      ? scheme.secondary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  doc.posted ? AppStrings.docPosted : AppStrings.docDraft,
                  style: TextStyle(
                      color:
                          doc.posted ? scheme.onSecondary : scheme.onSurface,
                      fontWeight: FontWeight.w700),
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
