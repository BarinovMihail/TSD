import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/feedback/feedback_service.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/app_database.dart';
import '../domain/barcode_assignment.dart';
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
final inventoryScreenControllerProvider = ChangeNotifierProvider.autoDispose
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

/// Результат попытки добавить штрихкод и обновить документ.
/// Используется окнами добавления/просмотра штрихкодов для единообразной
/// реакции: что показать и нужно ли закрыть окно.
enum AddBarcodeOutcome {
  /// POST успешен, документ перезагружен — штрихкод уже в данных.
  done,

  /// POST вернул НЕ сетевую ошибку (4xx/5xx/parse) — штрихкод НЕ записан.
  /// Нужно показать исходную ошибку и оставить окно открытым.
  failed,

  /// Нет ответа 1С (таймаут/обрыв), но документ удалось перезагрузить,
  /// и новый штрихкод там есть → считаем, что 1С всё же записала его.
  verifiedAfterTimeout,

  /// Нет ответа 1С И перезагрузка тоже не удалась / штрихкода в данных нет.
  /// Истинного состояния не знаем — даём пользователю «Повторить».
  inconclusive,
}

/// Результат удаления штрихкода и последующего обновления документа.
enum DeleteBarcodeOutcome {
  /// Сервис подтвердил удаление, документ перечитан.
  done,

  /// Сервис вернул HTTP-ошибку — удаление не выполнено.
  failed,

  /// Ответ сервиса потерян, но после обновления штрихкод исчез.
  verifiedAfterTimeout,

  /// Ответ сервиса потерян, а подтвердить удаление обновлением не удалось.
  inconclusive,
}

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

  /// Фильтр «Только без штрихкода»: когда включён, в списке видны только
  /// строки с barcodes.isEmpty. Данные и прогресс сканирования не меняет.
  bool onlyWithoutBarcode = false;

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

  /// Перечитать табличную часть с сервера (pull-to-refresh, повторный вход
  /// или после добавления штрихкода). Прогресс сканирования
  /// (КоличествоФактическое) накладывается из БД, поэтому не теряется.
  /// Возвращает результат: окна добавления/просмотра штрихкодов по нему
  /// понимают, удалось ли обновить данные.
  Future<Result<void>> reload() async {
    final scan = this.scan;
    if (scan == null) return const Success(null);
    final res = await repo.getTable(docCode);
    if (res is Failure<List<DocTableRow>>) return Failure(res.error);

    final rows = (res as Success<List<DocTableRow>>).value;
    scan.replaceRows(rows);
    await scan.hydrateFromDb();
    notifyListeners();
    return const Success(null);
  }

  /// Добавить штрихкод в 1С (POST /newBarcode) и перезагрузить документ.
  ///
  /// Смягчение сетевой ошибки: если POST не получил ответа (таймаут/обрыв),
  /// 1С могла всё же успеть записать штрихкод (он виден после ручного
  /// обновления). Поэтому в этом случае мы не показываем сразу «нет связи»,
  /// а пробуем перезагрузить документ — если штрихкод появился, считаем успехом.
  ///
  /// [prevBarcodes] — набор штрихкодов строки до отправки, чтобы после
  /// перезагрузки отличить «появился новый» от «ничего не изменилось».
  ///
  /// Возвращает пару (исход, ошибка). [AddBarcodeOutcome.failed] сопровождается
  /// исходной [ApiError] — её текст показывает пользователь.
  Future<({AddBarcodeOutcome outcome, ApiError? error})> addBarcodeAndReload({
    required String nomenclature,
    required String characteristic,
    required Set<String> prevBarcodes,
  }) async {
    final res = await repo.addBarcode(nomenclature, characteristic);
    return _finishBarcodeAdd(
      res,
      verifyAfterNetworkError: (rows) => _hasNewBarcode(rows, prevBarcodes),
    );
  }

  /// Привязать к строке уже нанесённый на товар штрихкод и перечитать
  /// документ. В отличие от генерации после сетевой ошибки проверяем
  /// конкретный штрихкод у конкретной строки.
  Future<({AddBarcodeOutcome outcome, ApiError? error})>
  addScannedBarcodeAndReload({
    required int lineNumber,
    required String nomenclature,
    required String characteristic,
    required String barcode,
  }) async {
    final normalized = barcode.trim();
    final res = await repo.addScannedBarcode(
      nomenclature,
      characteristic,
      normalized,
    );
    return _finishBarcodeAdd(
      res,
      verifyAfterNetworkError: (rows) => _rowHasBarcode(
        rows,
        lineNumber: lineNumber,
        barcode: normalized,
      ),
    );
  }

  /// Привязать неизвестный в текущем документе штрихкод к позиции из полного
  /// каталога номенклатуры. После сетевой ошибки проверяем результат напрямую
  /// через /barcode/{ШК}, потому что выбранной позиции может не быть в
  /// открытом документе и обычная проверка по его строкам здесь недостаточна.
  Future<({AddBarcodeOutcome outcome, ApiError? error})>
  assignUnknownBarcodeAndReload({
    required String nomenclature,
    required String characteristic,
    required String barcode,
  }) async {
    final normalized = barcode.trim();
    final res = await repo.addScannedBarcode(
      nomenclature,
      characteristic,
      normalized,
    );

    if (res is Success) {
      await reload();
      return (outcome: AddBarcodeOutcome.done, error: null);
    }

    final err = (res as Failure<void>).error;
    if (err is! NetworkError) {
      return (outcome: AddBarcodeOutcome.failed, error: err);
    }

    final lookup = await repo.getBarcodeAssignment(normalized);
    if (lookup is Success<BarcodeAssignment?> &&
        lookup.value?.matches(
              nomenclature: nomenclature,
              characteristic: characteristic,
            ) ==
            true) {
      await reload();
      return (
        outcome: AddBarcodeOutcome.verifiedAfterTimeout,
        error: null,
      );
    }
    return (outcome: AddBarcodeOutcome.inconclusive, error: null);
  }

  /// Удалить штрихкод в 1С и перечитать документ.
  ///
  /// Если ответ сервиса потерян, перечитываем документ и считаем операцию
  /// успешной только тогда, когда конкретный штрихкод исчез из строки.
  Future<({DeleteBarcodeOutcome outcome, ApiError? error})>
  deleteBarcodeAndReload({
    required int lineNumber,
    required String barcode,
  }) async {
    final normalized = barcode.trim();
    final res = await repo.deleteBarcode(normalized);

    if (res is Success) {
      // Сервис подтвердил удаление. Перечитываем документ, а при недоступности
      // списка всё равно сразу отражаем подтверждённое изменение локально.
      await reload();
      _removeBarcodeLocally(lineNumber: lineNumber, barcode: normalized);
      return (outcome: DeleteBarcodeOutcome.done, error: null);
    }

    final err = (res as Failure<void>).error;
    if (err is! NetworkError) {
      return (outcome: DeleteBarcodeOutcome.failed, error: err);
    }

    final reloadRes = await repo.getTable(docCode);
    if (reloadRes is Success<List<DocTableRow>>) {
      final scan = this.scan;
      if (scan != null) {
        scan.replaceRows(reloadRes.value);
        await scan.hydrateFromDb();
      }
      notifyListeners();
    }
    final removed =
        reloadRes is Success<List<DocTableRow>> &&
        !_rowHasBarcode(
          reloadRes.value,
          lineNumber: lineNumber,
          barcode: normalized,
        );
    return (
      outcome: removed
          ? DeleteBarcodeOutcome.verifiedAfterTimeout
          : DeleteBarcodeOutcome.inconclusive,
      error: null,
    );
  }

  Future<({AddBarcodeOutcome outcome, ApiError? error})> _finishBarcodeAdd(
    Result<void> res, {
    required bool Function(List<DocTableRow> rows) verifyAfterNetworkError,
  }) async {
    // Успех POST → стандартная перезагрузка.
    if (res is Success) {
      await reload();
      return (outcome: AddBarcodeOutcome.done, error: null);
    }
    // Провал не из-за таймаута/обрыва — штрихкод не записан, повторить.
    final err = (res as Failure).error;
    if (err is! NetworkError) {
      return (outcome: AddBarcodeOutcome.failed, error: err);
    }
    // Сетевая ошибка — 1С могла успеть записать. Проверяем перезагрузкой.
    final reloadRes = await repo.getTable(docCode);
    if (reloadRes is Success<List<DocTableRow>>) {
      final scan = this.scan;
      if (scan != null) {
        scan.replaceRows(reloadRes.value);
        await scan.hydrateFromDb();
      }
      notifyListeners();
    }
    final ok =
        reloadRes is Success &&
        verifyAfterNetworkError(scan?.rows ?? const []);
    return (
      outcome: ok
          ? AddBarcodeOutcome.verifiedAfterTimeout
          : AddBarcodeOutcome.inconclusive,
      error: null,
    );
  }

  /// Появился ли в строках штрихкод, которого не было в [prev].
  bool _hasNewBarcode(List<DocTableRow> rows, Set<String> prev) {
    for (final r in rows) {
      for (final b in r.barcodes) {
        if (!prev.contains(b)) return true;
      }
    }
    return false;
  }

  bool _rowHasBarcode(
    List<DocTableRow> rows, {
    required int lineNumber,
    required String barcode,
  }) {
    for (final row in rows) {
      if (row.lineNumber != lineNumber) continue;
      return row.barcodes.any((value) => value.trim() == barcode);
    }
    return false;
  }

  void _removeBarcodeLocally({
    required int lineNumber,
    required String barcode,
  }) {
    final scan = this.scan;
    if (scan == null) return;
    scan.replaceRows([
      for (final row in scan.rows)
        if (row.lineNumber == lineNumber)
          row.copyWith(
            barcodes: [
              for (final value in row.barcodes)
                if (value.trim() != barcode) value,
            ],
          )
        else
          row,
    ]);
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

  void toggleOnlyWithoutBarcode(bool v) {
    onlyWithoutBarcode = v;
    notifyListeners();
  }

  @override
  void dispose() {
    scan?.removeListener(_onScanChanged);
    super.dispose();
  }
}
