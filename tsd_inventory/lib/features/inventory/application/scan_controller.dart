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

/// Совпадение найдено — факт увеличен, прогресс сохранён.
class Found extends ScanOutcome {
  final DocTableRow row;
  const Found(this.row);
}

/// Штрихкод отсутствует во всех массивах «Штрихкоды» строк документа.
class NotFoundInDocument extends ScanOutcome {
  final String code;
  const NotFoundInDocument(this.code);
}

/// Одинаковый штрихкод найден у нескольких строк — нужен ручной выбор.
class Ambiguous extends ScanOutcome {
  final List<DocTableRow> candidates;
  const Ambiguous(this.candidates);
}

/// Отсканированное значение после trim пустое — игнорируем.
class ScanIgnored extends ScanOutcome {
  const ScanIgnored();
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
  }) : _repo = repo,
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

  /// Есть ли хоть одна строка с расхождением (факт ≠ учёту).
  bool get hasDiscrepancies => rows.any((r) => r.hasDiscrepancy);

  /// Число отсканированных позиций с расхождением (факт ≠ учёту).
  /// Учитываются только отсканированные строки (факт > 0), чтобы не
  /// считать за расхождения ещё не отсканированные позиции.
  int get scannedDiscrepancyCount =>
      rows.where((r) => r.isFound && r.hasDiscrepancy).length;

  /// Все ли позиции отсканированы (факт > 0 у каждой строки).
  bool get isFullyScanned => rows.isNotEmpty && scannedCount == total;

  /// Главная точка входа: отсканированный штрихкод сравнивается напрямую с
  /// массивами «Штрихкоды» строк текущего документа (без запроса в 1С).
  ///
  /// Поток:
  /// 1. trim; пустой результат → [ScanIgnored] (ничего не меняем).
  /// 2. Сопоставление строкам:
  ///    - ровно одно совпадение → +1 факт, persist, [Found];
  ///    - несколько → [Ambiguous] (диалог выбора);
  ///    - ни одного → [NotFoundInDocument] + сигнал ошибки.
  /// 3. После перезагрузки документа (или добавления нового штрихкода)
  ///    сканирование использует обновлённые массивы barcodes.
  Future<ScanOutcome> onScanned(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return const ScanIgnored();

    final res = _matcher.matchByBarcode(trimmed, rows);
    if (res.isNone) {
      await _feedback.error();
      return NotFoundInDocument(trimmed);
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

  /// Установить факт строки в [value] (с защитой от отрицательных) и сохранить.
  /// Переиспользуется для декремента и полного сброса факта сканирования.
  Future<void> _setActual(DocTableRow row, int value) async {
    final v = value < 0 ? 0 : value;
    final i = rows.indexWhere((r) => r.lineNumber == row.lineNumber);
    if (i == -1) return;
    rows[i] = rows[i].copyWith(qtyActual: v);
    await _db.upsertScanProgress(
      docCode: docCode,
      lineNo: rows[i].lineNumber,
      nomenclatureCode: rows[i].nomenclatureCode,
      qtyActual: rows[i].qtyActual,
      action: rows[i].action,
    );
    notifyListeners();
  }

  /// Убрать одну единицу из факта (не уходит ниже 0).
  /// Вызывается при долгом нажатии на отсканированной позиции.
  Future<void> decrementActual(DocTableRow row) =>
      _setActual(row, row.qtyActual - 1);

  /// Сбросить факт сканирования позиции в 0 (позиция становится
  /// «не отсканирована»). Запись прогресса остаётся в БД с qtyActual = 0.
  Future<void> resetActual(DocTableRow row) => _setActual(row, 0);

  /// Восстановление прогресса из БД при входе на экран.
  Future<void> hydrateFromDb() async {
    final saved = await _db.getScanProgress(docCode);
    for (var i = 0; i < rows.length; i++) {
      final s = saved[rows[i].lineNumber];
      if (s != null) {
        final serverActual = rows[i].qtyActual;
        // Нулевая локальная запись не должна скрывать факт, уже записанный
        // в 1С. Положительный локальный факт остаётся приоритетным: это может
        // быть ещё не отправленный прогресс текущего ТСД.
        final restoredActual = s.qtyActual == 0 && serverActual > 0
            ? serverActual
            : s.qtyActual;
        rows[i] = rows[i].copyWith(
          qtyActual: restoredActual,
          action: s.action ?? '',
        );
      }
    }
    notifyListeners();
  }

  /// Заменить строки свежими данными с сервера (reload). Прогресс (факт)
  /// восстанавливается отдельно через [hydrateFromDb]. Массивы barcodes
  /// обновляются здесь — новое сканирование сразу их использует.
  void replaceRows(List<DocTableRow> fresh) {
    rows = List.of(fresh);
    notifyListeners();
  }

  /// Отправка результатов в 1С. Успех → очистка локального прогресса
  /// и пометка документа как полностью отправленного (для метки в списке).
  Future<Result<void>> commit() async {
    final lines = <int, LineResult>{};
    for (final r in rows) {
      lines[r.lineNumber] = (qty: r.qtyActual, action: r.action);
    }
    final res = await _repo.postDocResult(docCode, lines);
    if (res is Success) {
      await _db.clearScanProgress(docCode);
      await _db.markDocCompleted(docCode);
    }
    return res;
  }
}
