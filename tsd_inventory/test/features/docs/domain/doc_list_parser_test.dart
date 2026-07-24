import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/docs/domain/doc_list_parser.dart';

void main() {
  test('парсит объект с числовыми ключами и русскими полями', () {
    final json = {
      '1': {
        'НомерДок': 'АЕ-00000002',
        'Подразделение': 'Отдел закупок',
        'Дата': '29.06.2026 10:54:23',
        'Проведен': true,
      },
      '2': {
        'НомерДок': 'АЕ-00000003',
        'Подразделение': 'Отдел закупок',
        'Дата': '01.07.2026 9:37:00',
        'Проведен': false,
      },
    };
    final list = parseDocList(json);
    expect(list.length, 2);
    // Сортировка по дате: 29.06 раньше 01.07.
    expect(list[0].number, 'АЕ-00000002');
    expect(list[0].department, 'Отдел закупок');
    expect(list[0].date, DateTime(2026, 6, 29, 10, 54, 23));
    expect(list[0].posted, true);
    expect(list[1].number, 'АЕ-00000003');
    // Час без ведущего нуля тоже разбирается.
    expect(list[1].date, DateTime(2026, 7, 1, 9, 37, 0));
    expect(list[1].posted, false);
  });

  test('пустое подразделение → null', () {
    final json = {
      '1': {
        'НомерДок': 'АЕ-00000001',
        'Подразделение': '',
        'Дата': '29.06.2026 10:54:23',
      },
    };
    final d = parseDocList(json).single;
    expect(d.department, isNull);
    expect(d.posted, false);
  });

  test('отсутствует НомерДок → элемент пропускается', () {
    final json = {
      '1': {'Подразделение': 'Отдел закупок', 'Дата': '29.06.2026 10:54:23'},
      '2': {'НомерДок': 'АЕ-00000002', 'Дата': '01.07.2026 9:37:00'},
    };
    final list = parseDocList(json);
    expect(list.length, 1);
    expect(list.single.number, 'АЕ-00000002');
  });

  test('невалидная дата → элемент пропускается, список не падает', () {
    final json = {
      '1': {'НомерДок': 'X-1', 'Дата': 'not-a-date'},
      '2': {'НомерДок': 'X-2', 'Дата': '01.07.2026 9:37:00'},
    };
    final list = parseDocList(json);
    expect(list.length, 1);
    expect(list.single.number, 'X-2');
  });

  test('Проведен сохраняется, если пришёл', () {
    final json = {
      '1': {
        'НомерДок': 'АЕ-00000002',
        'Дата': '29.06.2026 10:54:23',
        'Проведен': true,
      },
    };
    expect(parseDocList(json).single.posted, true);
  });

  test('Проведен имеет приоритет над прежним полем Posted', () {
    final json = {
      '1': {
        'НомерДок': 'АЕ-00000002',
        'Дата': '29.06.2026 10:54:23',
        'Проведен': false,
        'Posted': true,
      },
    };
    expect(parseDocList(json).single.posted, false);
  });

  test('прежнее поле Posted продолжает поддерживаться', () {
    final json = {
      '1': {
        'НомерДок': 'АЕ-00000002',
        'Дата': '29.06.2026 10:54:23',
        'Posted': true,
      },
    };
    expect(parseDocList(json).single.posted, true);
  });

  test('пустой объект → пустой список', () {
    expect(parseDocList({}), isEmpty);
  });

  test('не объект (например массив) → пустой список', () {
    expect(parseDocList([]), isEmpty);
  });
}
