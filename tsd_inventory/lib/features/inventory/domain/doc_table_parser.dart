import 'doc_table_row.dart';

/// Парсер ответа /code/: объект «номер строки → поля строки».
/// Количества приходят строками → приводим через int.tryParse.
/// Чистая функция, тестируется в unit-тестах.
List<DocTableRow> parseDocTable(Object? json) {
  if (json is! Map) return const [];
  final rows = <DocTableRow>[];
  for (final entry in json.entries) {
    if (entry.value is! Map) continue;
    final f = entry.value as Map;
    final line = int.tryParse(entry.key.toString()) ?? 0;
    rows.add(
      DocTableRow(
        lineNumber: line,
        inventoryNumber: f['ИнвентарныйНомер']?.toString() ?? '',
        nomenclature: f['Номенклатура']?.toString() ?? '',
        nomenclatureCode: f['НоменклатураКод']?.toString() ?? '',
        characteristic: f['Характеристика']?.toString() ?? '',
        series: f['Серия']?.toString() ?? '',
        seriesStatus: f['СтатусУказанияСерий']?.toString() ?? '0',
        fio: f['ФизическоеЛицо']?.toString() ?? '',
        qtyAccounting:
            int.tryParse(f['КоличествоПоДаннымУчета']?.toString() ?? '') ?? 0,
        qtyActual:
            int.tryParse(f['КоличествоФактическое']?.toString() ?? '') ?? 0,
        action: f['Действие']?.toString() ?? '',
        barcodes: parseBarcodes(f['Штрихкоды']),
      ),
    );
  }
  rows.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
  return rows;
}

/// Разбор массива «Штрихкоды» одной строки документа.
///
/// Контракт:
/// - значение может быть массивом, одиночной строкой/числом или объектом
///   с числовыми ключами (варианты сериализации массива в 1С);
/// - отсутствующее/null значение → пустой список;
/// - каждый штрихкод приводится к строке и trim-ится;
/// - пустые значения отбрасываются;
/// - штрихкоды НЕ преобразуются в числа, чтобы не потерять ведущие нули;
/// - у позиции может быть несколько штрихкодов.
List<String> parseBarcodes(Object? raw) {
  final Iterable<Object?> items;
  if (raw is List) {
    items = raw;
  } else if (raw is Map) {
    items = raw.values.cast<Object?>();
  } else if (raw is String || raw is num) {
    items = [raw];
  } else {
    return const [];
  }
  final result = <String>[];
  final seen = <String>{};
  for (final item in items) {
    final code = item?.toString().trim() ?? '';
    if (code.isNotEmpty && seen.add(code)) result.add(code);
  }
  return result;
}
