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
    rows.add(DocTableRow(
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
    ));
  }
  rows.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
  return rows;
}
