import 'package:flutter/foundation.dart';

import '../../../core/feedback/feedback_service.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/app_database.dart';
import '../data/inventory_repository.dart';
import '../domain/barcode_matcher.dart';
import '../domain/doc_table_row.dart';

/// Результат одного сканирования для UI.
sealed class ScanOutcome {
  const ScanOutcome();
}

class Found extends ScanOutcome {
  final DocTableRow row;
  const Found(this.row);
}

class NotFound extends ScanOutcome {
  final String code;
  const NotFound(this.code);
}

class Ambiguous extends ScanOutcome {
  final List<DocTableRow> candidates;
  const Ambiguous(this.candidates);
}

/// Оркестратор состояния сканирования одного документа.
class ScanController extends ChangeNotifier {
  ScanController({
    required this.docCode,
    required List<DocTableRow> initialRows,
    required InventoryRepository repo,
    required AppDatabase db,
    required BarcodeMatcher matcher,
    required FeedbackService feedback,
  })  : _repo = repo,
        _db = db,
        _matcher = matcher,
        _feedback = feedback,
        rows = List.of(initialRows);

  final String docCode;
  final InventoryRepository _repo;
  final AppDatabase _db;
  final BarcodeMatcher _matcher;
  final FeedbackService _feedback;

  List<DocTableRow> rows;

  int get total => rows.length;
  int get scannedCount => rows.where((r) => r.isFound).length;

  /// Главная точка входа: отсканированный код → реакция.
  Future<ScanOutcome> onScanned(String code) async {
    final res = _matcher.match(code, rows);
    if (res.isNone) {
      await _feedback.error();
      return NotFound(code);
    }
    if (res.isAmbiguous) {
      await _feedback.attention();
      return Ambiguous(res.exact);
    }
    // ровно одно совпадение → +1 факт, persist
    final row = res.exact.single;
    _incrementActual(row);
    await _feedback.success();
    final updated = rows.firstWhere((r) => r.lineNumber == row.lineNumber);
    await _db.upsertScanProgress(
      docCode: docCode,
      lineNo: updated.lineNumber,
      nomenclatureCode: updated.nomenclatureCode,
      qtyActual: updated.qtyActual,
      action: updated.action,
    );
    notifyListeners();
    return Found(updated);
  }

  /// Инкремент факта при выборе строки из диалога (множественное совпадение).
  Future<ScanOutcome> applyChoice(DocTableRow row) async {
    _incrementActual(row);
    await _feedback.success();
    final updated = rows.firstWhere((r) => r.lineNumber == row.lineNumber);
    await _db.upsertScanProgress(
      docCode: docCode,
      lineNo: updated.lineNumber,
      nomenclatureCode: updated.nomenclatureCode,
      qtyActual: updated.qtyActual,
      action: updated.action,
    );
    notifyListeners();
    return Found(updated);
  }

  void _incrementActual(DocTableRow row) {
    final i = rows.indexWhere((r) => r.lineNumber == row.lineNumber);
    if (i == -1) return;
    rows[i] = rows[i].copyWith(qtyActual: rows[i].qtyActual + 1);
  }

  /// Восстановление прогресса из БД при входе на экран.
  Future<void> hydrateFromDb() async {
    final saved = await _db.getScanProgress(docCode);
    for (var i = 0; i < rows.length; i++) {
      final s = saved[rows[i].lineNumber];
      if (s != null) {
        rows[i] =
            rows[i].copyWith(qtyActual: s.qtyActual, action: s.action ?? '');
      }
    }
    notifyListeners();
  }

  /// Отправка результатов в 1С. Успех → очистка локального прогресса.
  Future<Result<void>> commit() async {
    final lines = <int, LineResult>{};
    for (final r in rows) {
      lines[r.lineNumber] = (qty: r.qtyActual, action: r.action);
    }
    final res = await _repo.postDocResult(docCode, lines);
    if (res is Success) {
      await _db.clearScanProgress(docCode);
    }
    return res;
  }
}
