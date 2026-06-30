import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_parser.dart';

void main() {
  test('ключи-номера строк → int, количества-строки → int', () {
    final json = {
      '1': {
        'ИнвентарныйНомер': '44182',
        'Номенклатура': 'УЗ Дефектоскоп УД2-12',
        'НоменклатураКод': '00000000123',
        'Характеристика': '',
        'Серия': '',
        'СтатусУказанияСерий': '0',
        'ФизическоеЛицо': 'Белай Зоя Григорьевна',
        'КоличествоПоДаннымУчета': '1',
        'КоличествоФактическое': '1',
      },
      '2': {
        'ИнвентарныйНомер': '',
        'Номенклатура': 'Негатоскоп',
        'НоменклатураКод': '00000000456',
        'Характеристика': 'А3 Люмен',
        'Серия': '',
        'СтатусУказанияСерий': '0',
        'ФизическоеЛицо': 'Берлинская С.А.',
        'КоличествоПоДаннымУчета': '1',
        'КоличествоФактическое': '0',
      },
    };
    final rows = parseDocTable(json);
    expect(rows.length, 2);
    expect(rows[0].lineNumber, 1);
    expect(rows[0].inventoryNumber, '44182');
    expect(rows[0].nomenclatureCode, '00000000123');
    expect(rows[0].qtyAccounting, 1);
    expect(rows[0].qtyActual, 1);
    expect(rows[0].isFound, true);
    expect(rows[1].lineNumber, 2);
    expect(rows[1].qtyActual, 0);
    expect(rows[1].isFound, false);
  });

  test('сортировка по lineNumber', () {
    final json = {
      '10': {
        'Номенклатура': 'B',
        'НоменклатураКод': 'x',
        'КоличествоПоДаннымУчета': '0',
        'КоличествоФактическое': '0'
      },
      '2': {
        'Номенклатура': 'A',
        'НоменклатураКод': 'y',
        'КоличествоПоДаннымУчета': '0',
        'КоличествоФактическое': '0'
      },
    };
    final rows = parseDocTable(json);
    expect(rows.map((r) => r.lineNumber).toList(), [2, 10]);
  });

  test('невалидные количества → 0', () {
    final json = {
      '1': {
        'Номенклатура': 'X',
        'НоменклатураКод': 'k',
        'КоличествоПоДаннымУчета': 'не число',
        'КоличествоФактическое': '',
      }
    };
    final r = parseDocTable(json).single;
    expect(r.qtyAccounting, 0);
    expect(r.qtyActual, 0);
  });

  test('отсутствие НоменклатураКод → пустая строка (fallback)', () {
    final json = {
      '1': {
        'Номенклатура': 'X',
        'КоличествоПоДаннымУчета': '1',
        'КоличествоФактическое': '0'
      }
    };
    expect(parseDocTable(json).single.nomenclatureCode, '');
  });

  test('нечисловой ключ строки → lineNumber 0, не валит', () {
    final json = {
      'abc': {
        'Номенклатура': 'X',
        'НоменклатураКод': 'k',
        'КоличествоПоДаннымУчета': '0',
        'КоличествоФактическое': '0'
      },
    };
    final r = parseDocTable(json).single;
    expect(r.lineNumber, 0);
  });
}
