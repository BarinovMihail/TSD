import 'doc_table_row.dart';

/// Результат сопоставления отсканированного штрихкода строкам таблицы.
class MatchResult {
  final List<DocTableRow> exact;
  const MatchResult(this.exact);
  bool get isUnique => exact.length == 1;
  bool get isNone => exact.isEmpty;
  bool get isAmbiguous => exact.length > 1;
}

/// Сопоставление отсканированного штрихкода строкам документа.
///
/// Штрихкод сравнивается напрямую со всеми элементами массивов «Штрихкоды»
/// строк (полученных при загрузке документа через GET /hs/inventory/code/).
/// Никакого обращения к регистру сведений 1С при сканировании не происходит.
///
/// Правила сравнения:
/// - к отсканированному значению применяется [trim];
/// - пустой результат игнорируется (матчер его не обрабатывает — см.
///   [ScanController.onScanned]);
/// - сравнение строковое, без преобразования в int, ведущие нули сохраняются;
/// - у позиции может быть несколько штрихкодов: совпадение с любым из них
///   отмечает эту позицию;
/// - если одинаковый штрихкод найден у нескольких строк → isAmbiguous
///   (диалог выбора пользователя).
class BarcodeMatcher {
  /// Сопоставление отсканированного [code] строкам [rows] по их массивам
  /// штрихкодов. [code] здесь ожидается уже обрезанным от пробелов вызывающей
  /// стороной; для надёжности trim применяется и здесь, и к каждому штрихкоду
  /// строки.
  MatchResult matchByBarcode(String code, List<DocTableRow> rows) {
    final c = code.trim();
    if (c.isEmpty) return MatchResult(const []);
    final hits = rows
        .where((r) => r.barcodes.any((b) => b.trim() == c))
        .toList();
    return MatchResult(hits);
  }

  /// Сопоставление позиции из регистра сведений со строками документа.
  /// Название и характеристика сравниваются без учёта регистра и лишних
  /// пробелов, потому что оба значения приходят из разных HTTP-сервисов 1С.
  MatchResult matchByNomenclatureCharacteristic(
    String nomenclature,
    String characteristic,
    List<DocTableRow> rows,
  ) {
    final normalizedNomenclature = _normalizeText(nomenclature);
    if (normalizedNomenclature.isEmpty) return MatchResult(const []);
    final normalizedCharacteristic = _normalizeText(characteristic);
    final hits = rows
        .where(
          (row) =>
              _normalizeText(row.nomenclature) == normalizedNomenclature &&
              _normalizeText(row.characteristic) == normalizedCharacteristic,
        )
        .toList();
    return MatchResult(hits);
  }

  String _normalizeText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}
