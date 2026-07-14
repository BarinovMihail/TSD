import 'package:flutter/foundation.dart';

import '../../../core/feedback/feedback_service.dart';
import '../../../core/network/api_error.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/app_database.dart';
import '../data/inventory_repository.dart';
import '../domain/barcode_info.dart';
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

/// Штрихкод не зарегистрирован в 1С (регистр сведений вернул пустой ответ).
class BarcodeNotRegistered extends ScanOutcome {
  final String code;
  const BarcodeNotRegistered(this.code);
}

/// Номенклатура по штрихкоду найдена в 1С, но не сопоставлена ни одной строке
/// документа (нет строки с такой парой Номенклатура + Характеристика).
class NotFoundInDocument extends ScanOutcome {
  final String code;
  final BarcodeInfo info;
  const NotFoundInDocument(this.code, this.info);
}

/// Сетевая/серверная ошибка при запросе данных штрихкода из 1С.
class LookupError extends ScanOutcome {
  final String code;
  final ApiError error;
  const LookupError(this.code, this.error);
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

  /// Есть ли хоть одна строка с расхождением (факт ≠ учёту).
  bool get hasDiscrepancies => rows.any((r) => r.hasDiscrepancy);

  /// Число отсканированных позиций с расхождением (факт ≠ учёту).
  /// Учитываются только отсканированные строки (факт > 0), чтобы не
  /// считать за расхождения ещё не отсканированные позиции.
  int get scannedDiscrepancyCount =>
      rows.where((r) => r.isFound && r.hasDiscrepancy).length;

  /// Все ли позиции отсканированы (факт > 0 у каждой строки).
  bool get isFullyScanned => rows.isNotEmpty && scannedCount == total;

  /// Главная точка входа: отсканированный штрихкод → данные из 1С → реакция.
  ///
  /// Поток:
  /// 1. GET /hs/inventory/barcode/{code} → пара (Номенклатура, Характеристика).
  /// 2. Пара строго сопоставляется строкам документа:
  ///    - ровно одно совпадение → +1 факт, persist, Found;
  ///    - несколько → Ambiguous (диалог выбора);
  ///    - ни одного → NotFoundInDocument.
  /// 3. Штрихкод не зарегистрирован в 1С (пустой ответ) → BarcodeNotRegistered.
  /// 4. Сетевая/серверная ошибка → LookupError.
  Future<ScanOutcome> onScanned(String code) async {
    final infoRes = await _repo.getBarcodeInfo(code);
    if (infoRes is Failure<BarcodeInfo?>) {
      await _feedback.error();
      return LookupError(code, infoRes.error);
    }
    final info = (infoRes as Success<BarcodeInfo?>).value;
    if (info == null) {
      await _feedback.error();
      return BarcodeNotRegistered(code);
    }

    final res = _matcher.matchByNomenclatureCharacteristic(
        info.nomenclature, info.characteristic, rows);
    if (res.isNone) {
      await _feedback.error();
      return NotFoundInDocument(code, info);
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
        rows[i] =
            rows[i].copyWith(qtyActual: s.qtyActual, action: s.action ?? '');
      }
    }
    notifyListeners();
  }

  /// Заменить строки свежими данными с сервера (reload). Прогресс (факт)
  /// восстанавливается отдельно через [hydrateFromDb].
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

  /// Добавить новую строку номенклатуры в документ, когда отсканированный
  /// штрихкод найден в 1С, но не сопоставлен строке документа.
  /// POST /hs/inventory/newStr с {Номенклатура, Характеристика} из ответа
  /// /barcode/ → перечитать табличную часть → поставить факт = 1 по добавленной
  /// номенклатуре.
  ///
  /// Возвращает Success, если строка добавлена и найдена после перезагрузки,
  /// иначе Failure (сеть/сервер или строка не вернулась от 1С).
  Future<Result<void>> addMissingLine(BarcodeInfo info) async {
    final addRes = await _repo.addNewLine(
        docCode, info.nomenclature, info.characteristic);
    if (addRes is Failure) return addRes;

    // Перезагружаем табличную часть, чтобы появилась новая строка.
    final tableRes = await _repo.getTable(docCode);
    return tableRes.maybeWhen(
      onValue: (fresh) async {
        replaceRows(fresh);
        // Восстанавливаем прогресс по уже отсканированным строкам.
        await hydrateFromDb();
        // Ищем добавленную строку через тот же матчер по паре
        // (Номенклатура, Характеристика), что и при сканировании.
        final match = _matcher.matchByNomenclatureCharacteristic(
            info.nomenclature, info.characteristic, rows);
        if (match.exact.isEmpty) {
          // 1С не вернула строку с такой парой — не получилось её отметить.
          return const Failure(ParseError(
              'Новая строка не найдена после добавления'));
        }
        final i = rows.indexWhere(
            (r) => r.lineNumber == match.exact.first.lineNumber);
        rows[i] = rows[i].copyWith(qtyActual: 1);
        await _db.upsertScanProgress(
          docCode: docCode,
          lineNo: rows[i].lineNumber,
          nomenclatureCode: rows[i].nomenclatureCode,
          qtyActual: rows[i].qtyActual,
          action: rows[i].action,
        );
        await _feedback.success();
        notifyListeners();
        return const Success(null);
      },
      orElse: (err) => Failure(err),
    );
  }
}
