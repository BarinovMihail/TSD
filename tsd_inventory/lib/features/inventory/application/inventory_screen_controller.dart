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
final inventoryScreenControllerProvider =
    ChangeNotifierProvider.family<InventoryScreenController, String>(
        (ref, docCode) {
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
