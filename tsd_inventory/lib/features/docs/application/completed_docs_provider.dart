import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/features/inventory/application/providers.dart';

/// Множество кодов документов, полностью отправленных в 1С (по «Завершить»).
/// Используется для метки «✓ Отправлен» в списке документов.
/// После успешной отправки экран инвентаря инвалидирует этот провайдер.
final completedDocsProvider = FutureProvider<Set<String>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.allCompletedDocCodes();
});
