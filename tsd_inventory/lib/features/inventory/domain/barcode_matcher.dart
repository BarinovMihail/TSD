import 'doc_table_row.dart';

/// Результат сопоставления штрихкода строкам таблицы.
class MatchResult {
  final List<DocTableRow> exact;
  const MatchResult(this.exact);
  bool get isUnique => exact.length == 1;
  bool get isNone => exact.isEmpty;
  bool get isAmbiguous => exact.length > 1;
}

/// Сопоставление штрихкода строкам. Ключ — НоменклатураКод (решение дизайна).
/// Fallback на Инв.№/Серию/Номенклатуру ТОЛЬКО если НоменклатураКод пуст у всех строк.
class BarcodeMatcher {
  MatchResult match(String code, List<DocTableRow> rows) {
    final norm = normalize(code);
    if (norm.isEmpty) return MatchResult(const []);

    // 1) Основной ключ: НоменклатураКод
    var hits = rows.where((r) => normalize(r.nomenclatureCode) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);

    // 2) Fallback только если основной ключ пуст у всех строк
    final anyPrimary = rows.any((r) => r.nomenclatureCode.trim().isNotEmpty);
    if (anyPrimary) return MatchResult(const []);

    hits = rows.where((r) => normalize(r.inventoryNumber) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);

    hits = rows.where((r) => normalize(r.series) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);

    hits = rows.where((r) => normalize(r.nomenclature) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);

    return MatchResult(const []);
  }

  /// Нормализация для сопоставления:
  /// - восклицательные знаки заменяются пробелами (сканер шлёт «618810!!!!!!»
  ///   вместо добивки пробелами — сохраняем ширину кода);
  /// - trailing-пробелы убираются, чтобы код с добивкой («000123      ») и без
  ///   неё совпадали, даже если в 1С длина колонки фиксирована.
  /// Регистр не меняется (коды 1С — case-sensitive).
  String normalize(String s) => s.replaceAll('!', ' ').trim();
}
