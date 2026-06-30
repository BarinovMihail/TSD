import 'package:logging/logging.dart';

import 'doc_list_item.dart';

final _log = Logger('doc_list_parser');

/// Парсер ответа /fio/: массив объектов, обёрнутых в "#value".
/// Чистая функция, не зависит от Flutter/dio — тестируется в unit-тестах.
List<DocListItem> parseDocList(Object? json) {
  if (json is! List) return const [];
  final result = <DocListItem>[];
  for (final el in json) {
    if (el is! Map) continue;
    // Обход обёртки #value; при отсутствии — сам элемент.
    final v = (el['#value'] as Map?) ?? el;
    try {
      final rawDate = v['Date']?.toString();
      if (rawDate == null) continue;
      final date = DateTime.parse(rawDate);
      result.add(DocListItem(
        ref: v['Ref']?.toString() ?? '',
        number: v['Number']?.toString() ?? '',
        date: date,
        posted: v['Posted'] as bool? ?? false,
        organizationGuid: _guidOrNull(v['Организация']),
        departmentGuid: _guidOrNull(v['Подразделение']),
        responsibleGuid: _guidOrNull(v['Ответственный']),
      ));
    } catch (e) {
      _log.warning('Пропуск элемента списка документов из-за ошибки парсинга: $e');
    }
  }
  return result;
}

String? _guidOrNull(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
