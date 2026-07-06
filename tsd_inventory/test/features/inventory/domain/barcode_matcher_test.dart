import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

DocTableRow _row(int line,
        {String nom = '', String char = '', String code = ''}) =>
    DocTableRow(
      lineNumber: line,
      inventoryNumber: '',
      nomenclature: nom,
      nomenclatureCode: code,
      characteristic: char,
      series: '',
      seriesStatus: '0',
      fio: '',
      qtyAccounting: 1,
      qtyActual: 0,
      action: '',
    );

void main() {
  group('matchByNomenclatureCharacteristic', () {
    test('уникальное совпадение по паре Номенклатура+Характеристика', () {
      final rows = [
        _row(1, nom: 'Монитор', char: '23,5" Samsung №CWGCH4ZR503628'),
        _row(2, nom: 'Клавиатура', char: ''),
      ];
      final r = BarcodeMatcher().matchByNomenclatureCharacteristic(
          'Монитор', '23,5" Samsung №CWGCH4ZR503628', rows);
      expect(r.isUnique, true);
      expect(r.exact.single.lineNumber, 1);
    });

    test('совпадение когда характеристика пустая у строки и у запроса', () {
      final rows = [_row(1, nom: 'Клавиатура', char: '')];
      final r = BarcodeMatcher().matchByNomenclatureCharacteristic(
          'Клавиатура', '', rows);
      expect(r.isUnique, true);
      expect(r.exact.single.lineNumber, 1);
    });

    test('несколько строк с одинаковой парой → ambiguous', () {
      final rows = [
        _row(1, nom: 'Монитор', char: 'Black'),
        _row(2, nom: 'Монитор', char: 'Black'), // дубль пары
      ];
      final r = BarcodeMatcher().matchByNomenclatureCharacteristic(
          'Монитор', 'Black', rows);
      expect(r.isAmbiguous, true);
      expect(r.exact.length, 2);
    });

    test('разная характеристика → не совпадает', () {
      final rows = [
        _row(1, nom: 'Монитор', char: 'Black'),
        _row(2, nom: 'Монитор', char: 'White'),
      ];
      final r = BarcodeMatcher()
          .matchByNomenclatureCharacteristic('Монитор', 'White', rows);
      expect(r.isUnique, true);
      expect(r.exact.single.lineNumber, 2);
    });

    test('номенклатура есть, характеристика другая → none', () {
      final rows = [_row(1, nom: 'Монитор', char: 'Black')];
      final r = BarcodeMatcher()
          .matchByNomenclatureCharacteristic('Монитор', 'White', rows);
      expect(r.isNone, true);
    });

    test('нет такой номенклатуры → none', () {
      final rows = [_row(1, nom: 'Монитор', char: '')];
      final r = BarcodeMatcher()
          .matchByNomenclatureCharacteristic('Принтер', '', rows);
      expect(r.isNone, true);
    });

    test('пустая номенклатура в запросе → none', () {
      final rows = [_row(1, nom: 'Монитор', char: '')];
      expect(
          BarcodeMatcher()
              .matchByNomenclatureCharacteristic('', '', rows)
              .isNone,
          true);
    });

    test('нормализация: регистр не важен', () {
      final rows = [_row(1, nom: 'Монитор', char: 'Black')];
      expect(
          BarcodeMatcher()
              .matchByNomenclatureCharacteristic('МОНИТОР', 'BLACK', rows)
              .isUnique,
          true);
    });

    test('нормализация: лишние пробелы коллапсируются', () {
      final rows = [_row(1, nom: 'Монитор 24', char: 'Black')];
      expect(
          BarcodeMatcher()
              .matchByNomenclatureCharacteristic(
                  '  Монитор   24 ', '  Black  ', rows)
              .isUnique,
          true);
    });
  });

  group('normalizeCode (для addMissingLine)', () {
    test('восклицательные знаки → пробелы, trim', () {
      expect(BarcodeMatcher().normalizeCode('618810!!!!!'), '618810');
    });

    test('trailing пробелы убираются', () {
      expect(BarcodeMatcher().normalizeCode('000123      '), '000123');
    });
  });
}
