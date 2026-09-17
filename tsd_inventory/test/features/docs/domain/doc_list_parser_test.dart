import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/docs/domain/doc_list_parser.dart';

void main() {
  test('парсит объект с числовыми ключами и русскими полями', () {
    final json = {
      '1': {
        'НомерДок': 'АЕ-00000002',
        'Подразделение': 'Бюро технического обслуживания и связи',
        'ФизическоеЛицо': 'Порядина Мария Михайловна',
        'Дата': '15.07.2026 11:49:57',
        'Проведен': true,
      },
      '2': {
        'НомерДок': 'АЕ-00000003',
        'Подразделение': 'Бюро технического обслуживания и связи',
        'ФизическоеЛицо': 'Калинин Юрий Алексеевич',
        'Дата': '30.07.2026 9:54:09',
        'Проведен': false,
      },
    };
    final list = parseDocList(json);
    expect(list.length, 2);
    // Сортировка по дате: 15.07 раньше 30.07.
    expect(list[0].number, 'АЕ-00000002');
    expect(list[0].department, 'Бюро технического обслуживания и связи');
    expect(list[0].person, 'Порядина Мария Михайловна');
    expect(list[0].date, DateTime(2026, 7, 15, 11, 49, 57));
    expect(list[0].posted, true);
    expect(list[1].number, 'АЕ-00000003');
    expect(list[1].person, 'Калинин Юрий Алексеевич');
    // Час без ведущего нуля тоже разбирается.
    expect(list[1].date, DateTime(2026, 7, 30, 9, 54, 9));
    expect(list[1].posted, false);
  });

  test('отсутствует/пустое ФизическоеЛицо → null', () {
    final json = {
      '1': {
        'НомерДок': 'АЕ-00000001',
        'Дата': '29.06.2026 10:54:23',
      },
      '2': {
        'НомерДок': 'АЕ-00000002',
        'ФизическоеЛицо': '  ',
        'Дата': '30.07.2026 9:54:09',
      },
    };
    final list = parseDocList(json);
    expect(list[0].person, isNull);
    expect(list[1].person, isNull);
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
