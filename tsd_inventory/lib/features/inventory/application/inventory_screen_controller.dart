import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/feedback/feedback_service.dart';
import '../../../core/result/result.dart';
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
    res.maybeWhen(
      onValue: (rows) async {
        scan.replaceRows(rows);
        await scan.hydrateFromDb();
        notifyListeners();
      },
      orElse: (_) {},
    );
    return res;
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
    reloadRes.maybeWhen(
      onValue: (rows) {
        scan?.replaceRows(rows);
        notifyListeners();
      },
      orElse: (_) {},
    );
    final ok =
        reloadRes is Success &&
        _hasNewBarcode(scan?.rows ?? const [], prevBarcodes);
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
