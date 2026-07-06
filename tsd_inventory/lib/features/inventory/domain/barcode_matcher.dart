import 'doc_table_row.dart';

/// Результат сопоставления штрихкода строкам таблицы.
class MatchResult {
  final List<DocTableRow> exact;
  const MatchResult(this.exact);
  bool get isUnique => exact.length == 1;
  bool get isNone => exact.isEmpty;
  bool get isAmbiguous => exact.length > 1;
}

/// Сопоставление отсканированной номенклатуры строкам таблицы.
///
/// Раньше ключом был НоменклатураКод (он же штрихкод). Теперь сканер шлёт код
/// штрихкода, по которому 1С через регистр сведений возвращает пару
/// (Номенклатура, Характеристика) — именно она и сопоставляется строкам.
class BarcodeMatcher {
  /// Сопоставление по паре (Номенклатура, Характеристика), полученной из 1С
  /// по штрихкоду. Строгое равенство обоих полей (с нормализацией).
  /// Несколько строк с идентичной парой → isAmbiguous (диалог выбора).
  MatchResult matchByNomenclatureCharacteristic(
    String nomenclature,
    String characteristic,
    List<DocTableRow> rows,
  ) {
    final nomNorm = normalize(nomenclature);
    if (nomNorm.isEmpty) return MatchResult(const []);
    final charNorm = normalize(characteristic);

    final hits = rows
        .where((r) =>
            normalize(r.nomenclature) == nomNorm &&
            normalize(r.characteristic) == charNorm)
        .toList();
    return MatchResult(hits);
  }

  /// Нормализация текста для сопоставления:
  /// - trim и коллапс повторяющихся пробелов в один;
  /// - case-insensitive (имена номенклатуры — русский текст из той же 1С,
  ///   различия регистра несущественны).
  /// Сравнение названий надёжнее, чем кодов, поэтому регистр игнорируем
  /// (для кодов в [addMissingLine] используется отдельный [normalizeCode]).
  String normalize(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return t.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  /// Нормализация КОДА номенклатуры для [addMissingLine]:
  /// - восклицательные знаки заменяются пробелами (сканер шлёт «618810!!!!!!»
  ///   вместо добивки пробелами — сохраняем ширину кода);
  /// - trailing-пробелы убираются, чтобы код с добивкой («000123      ») и без
  ///   неё совпадали, даже если в 1С длина колонки фиксирована.
  /// Регистр не меняется (коды 1С — case-sensitive).
  String normalizeCode(String s) => s.replaceAll('!', ' ').trim();
}
