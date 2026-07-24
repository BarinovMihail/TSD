import 'package:logging/logging.dart';

import 'doc_list_item.dart';

final _log = Logger('doc_list_parser');

/// Парсер ответа /fio/: объект с числовыми ключами, значениями — документы.
/// Пример: {"1": {"НомерДок":"АЕ-00000002","Подразделение":"Отдел закупок","Дата":"29.06.2026 10:54:23","Проведен":true}}
/// Чистая функция, не зависит от Flutter/dio — тестируется в unit-тестах.
List<DocListItem> parseDocList(Object? json) {
  if (json is! Map) return const [];
  final result = <DocListItem>[];
  for (final entry in json.entries) {
    final v = entry.value;
    if (v is! Map) continue;
    try {
      final number = v['НомерДок']?.toString().trim();
      if (number == null || number.isEmpty) continue;
      final date = _parseRuDate(v['Дата']?.toString());
      if (date == null) continue;
      result.add(DocListItem(
        number: number,
        date: date,
        department: _trimOrNull(v['Подразделение']),
        // Во время обновления сервера поддерживаем и прежнее английское имя.
        // Если новое поле присутствует, именно оно считается источником истины.
        posted: v.containsKey('Проведен')
            ? v['Проведен'] == true
            : v['Posted'] == true,
      ));
    } catch (e) {
      _log.warning('Пропуск элемента списка документов из-за ошибки парсинга: $e');
    }
  }
  // Упорядочиваем по дате (как на сервере), на случай перемешивания ключей.
  result.sort((a, b) => a.date.compareTo(b.date));
  return result;
}

/// Разбирает дату вида "dd.MM.yyyy H:mm:ss" (час может быть без ведущего нуля).
DateTime? _parseRuDate(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final m = RegExp(
    r'^(\d{2})\.(\d{2})\.(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})$',
  ).firstMatch(s);
  if (m == null) {
    // Подстраховка: вдруг придёт ISO — пробуем стандартный парсер.
    return DateTime.tryParse(s);
  }
  return DateTime(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}

String? _trimOrNull(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
