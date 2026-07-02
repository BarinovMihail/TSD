import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/feedback_service.dart';
import '../../../core/storage/app_database.dart';
import '../domain/barcode_matcher.dart';
import '../domain/doc_table_row.dart';
import '../data/inventory_repository.dart';
import 'providers.dart';
import 'scan_controller.dart';

/// Семейство контроллеров экрана по коду документа.
/// autoDispose: при выходе с экрана (контекст убран из дерева) провайдер
/// диспозится → при повторном входе пересоздаётся → init() зовёт запрос к
/// серверу заново (свежие данные). Прогресс сканирования при этом не теряется:
/// он хранится в БД и восстанавливается через hydrateFromDb().
final inventoryScreenControllerProvider =
    ChangeNotifierProvider.autoDispose
        .family<InventoryScreenController, String>((ref, docCode) {
  // keepAlive НЕ нужен: хотим пересоздание при выходе/входе.
  return InventoryScreenController(
    docCode: docCode,
    repo: ref.watch(inventoryRepositoryProvider),
    db: ref.watch(appDatabaseProvider),
    matcher: BarcodeMatcher(),
    feedback: FeedbackService(),
  )..init();
});

class InventoryScreenController extends ChangeNotifier {
  InventoryScreenController({
    required this.docCode,
    required this.repo,
    required this.db,
    required this.matcher,
    required this.feedback,
  });

  final String docCode;
  final InventoryRepository repo;
  final AppDatabase db;
  final BarcodeMatcher matcher;
  final FeedbackService feedback;

  bool loading = true;
  String? loadError;
  ScanController? scan;

  String searchQuery = '';
  bool unscannedFirst = true;

  Future<void> init() async {
    final res = await repo.getTable(docCode);
    final rows = res.maybeWhen<List<DocTableRow>?>(
      onValue: (v) => v,
      orElse: (err) {
        loadError = err.userMessage;
        return null;
      },
    );
    if (rows != null) {
      scan = ScanController(
        docCode: docCode,
        initialRows: rows,
        repo: repo,
        db: db,
        matcher: matcher,
        feedback: feedback,
      );
      await scan!.hydrateFromDb();
      scan!.addListener(_onScanChanged);
    }
    loading = false;
    notifyListeners();
  }

  /// Перечитать табличную часть с сервера (pull-to-refresh или повторный вход).
  /// Прогресс сканирования (КоличествоФактическое) накладывается из БД, поэтому
  /// не теряется.
  Future<void> reload() async {
    final scan = this.scan;
    if (scan == null) return;
    final res = await repo.getTable(docCode);
    res.maybeWhen(
      onValue: (rows) async {
        scan.replaceRows(rows);
        await scan.hydrateFromDb();
        notifyListeners();
      },
      orElse: (_) {},
    );
  }

  void _onScanChanged() => notifyListeners();

  void setSearch(String q) {
    searchQuery = q;
    notifyListeners();
  }

  void toggleSort(bool v) {
    unscannedFirst = v;
    notifyListeners();
  }

  @override
  void dispose() {
    scan?.removeListener(_onScanChanged);
    super.dispose();
  }
}
