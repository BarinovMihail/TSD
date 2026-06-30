import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/docs/domain/doc_list_parser.dart';

void main() {
  test('обходит обёртку #value и парсит поля', () {
    final json = [
      {
        '#value': {
          'Ref': 'bdb920e7-738f-11f1-bb02-e83525ee0c0b',
          'Date': '2026-06-29T10:54:23',
          'Number': 'АЕ-00000002',
          'Posted': true,
          'Организация': '3d074bd8-4bcb-11e5-9b25-000c299754cd',
          'Подразделение': '141190b0-bb5d-11e5-9b78-002590fbf13d',
        }
      },
    ];
    final list = parseDocList(json);
    expect(list.length, 1);
    final d = list.single;
    expect(d.ref, 'bdb920e7-738f-11f1-bb02-e83525ee0c0b');
    expect(d.number, 'АЕ-00000002');
    expect(d.posted, true);
    expect(d.date, DateTime.parse('2026-06-29T10:54:23'));
    expect(d.organizationGuid, '3d074bd8-4bcb-11e5-9b25-000c299754cd');
    expect(d.departmentGuid, '141190b0-bb5d-11e5-9b78-002590fbf13d');
  });

  test('пустые GUID → null', () {
    final json = [
      {
        '#value': {
          'Ref': 'ref1',
          'Date': '2026-06-29T10:54:23',
          'Number': 'АЕ-00000001',
          'Posted': false,
          'Организация': '',
          'Подразделение': '',
          'Ответственный': '',
        }
      },
    ];
    final d = parseDocList(json).single;
    expect(d.organizationGuid, isNull);
    expect(d.departmentGuid, isNull);
    expect(d.responsibleGuid, isNull);
    expect(d.posted, false);
  });

  test('невалидная дата → элемент пропускается, список не падает', () {
    final json = [
      {
        '#value': {'Ref': 'bad', 'Date': 'not-a-date', 'Number': 'X-1', 'Posted': true}
      },
      {
        '#value': {'Ref': 'good', 'Date': '2026-06-29T10:54:23', 'Number': 'X-2', 'Posted': true}
      },
    ];
    final list = parseDocList(json);
    expect(list.length, 1);
    expect(list.single.ref, 'good');
  });

  test('отсутствие #value → элемент трактуется как сам Map', () {
    final json = [
      {'Ref': 'direct', 'Date': '2026-06-29T10:54:23', 'Number': 'D-1', 'Posted': true},
    ];
    final d = parseDocList(json).single;
    expect(d.ref, 'direct');
    expect(d.number, 'D-1');
  });

  test('пустой массив → пустой список', () {
    expect(parseDocList([]), isEmpty);
  });
}
