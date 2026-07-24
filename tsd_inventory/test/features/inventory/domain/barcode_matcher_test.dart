import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

DocTableRow _row(
  int line, {
  String? nomenclature,
  String characteristic = '',
  List<String> barcodes = const [],
}) => DocTableRow(
  lineNumber: line,
  inventoryNumber: '',
  nomenclature: nomenclature ?? 'N$line',
  nomenclatureCode: 'k$line',
  characteristic: characteristic,
  series: '',
  seriesStatus: '0',
  fio: '',
  qtyAccounting: 1,
  qtyActual: 0,
  action: '',
  barcodes: barcodes,
);

void main() {
  group('matchByBarcode', () {
    test('совпадение с единственным штрихкодом позиции → unique', () {
      final rows = [
        _row(1, barcodes: ['2000000009100']),
        _row(2, barcodes: ['111']),
      ];
      final r = BarcodeMatcher().matchByBarcode('2000000009100', rows);
      expect(r.isUnique, true);
      expect(r.exact.single.lineNumber, 1);
    });

    test('совпадение со вторым/последующим штрихкодом позиции → unique', () {
      final rows = [
        _row(1, barcodes: ['111', '222', '333']),
      ];
      // Совпадение с третьим штрихкодом тоже отмечает позицию.
      expect(BarcodeMatcher().matchByBarcode('333', rows).isUnique, true);
      expect(BarcodeMatcher().matchByBarcode('222', rows).isUnique, true);
      final r = BarcodeMatcher().matchByBarcode('111', rows);
      expect(r.exact.single.lineNumber, 1);
    });

    test('отсутствие совпадения → none', () {
      final rows = [
        _row(1, barcodes: ['111']),
      ];
      expect(BarcodeMatcher().matchByBarcode('999', rows).isNone, true);
    });

    test('одинаковый штрихкод у нескольких строк → ambiguous', () {
      final rows = [
        _row(1, barcodes: ['111', 'SHARED']),
        _row(2, barcodes: ['SHARED']),
      ];
      final r = BarcodeMatcher().matchByBarcode('SHARED', rows);
      expect(r.isAmbiguous, true);
      expect(r.exact.length, 2);
    });

    test('пробелы вокруг отсканированного значения игнорируются (trim)', () {
      final rows = [
        _row(1, barcodes: ['111']),
      ];
      expect(BarcodeMatcher().matchByBarcode('  111  ', rows).isUnique, true);
    });

    test('ведущие нули сохраняются: «007890» ≠ «7890»', () {
      final rows = [
        _row(1, barcodes: ['007890']),
      ];
      expect(BarcodeMatcher().matchByBarcode('007890', rows).isUnique, true);
      expect(BarcodeMatcher().matchByBarcode('7890', rows).isNone, true);
    });

    test('пустой отсканированный код → none', () {
      final rows = [
        _row(1, barcodes: ['111']),
      ];
      expect(BarcodeMatcher().matchByBarcode('', rows).isNone, true);
    });

    test('совпадение по строковому равенству, без int-преобразования', () {
      // «0123» и «123» как строки различны.
      final rows = [
        _row(1, barcodes: ['0123']),
      ];
      expect(BarcodeMatcher().matchByBarcode('123', rows).isNone, true);
      expect(BarcodeMatcher().matchByBarcode('0123', rows).isUnique, true);
    });

    test('позиция без штрихкодов не participates', () {
      final rows = [
        _row(1, barcodes: []),
        _row(2, barcodes: ['111']),
      ];
      expect(
        BarcodeMatcher().matchByBarcode('111', rows).exact.single.lineNumber,
        2,
      );
    });
  });

  group('matchByNomenclatureCharacteristic', () {
    test('сопоставляет позицию из регистра со строкой документа', () {
      final rows = [
        _row(1, nomenclature: 'Монитор', characteristic: 'Black'),
        _row(2, nomenclature: 'Клавиатура', characteristic: 'Белая'),
      ];

      final result = BarcodeMatcher().matchByNomenclatureCharacteristic(
        'Клавиатура',
        'Белая',
        rows,
      );

      expect(result.isUnique, true);
      expect(result.exact.single.lineNumber, 2);
    });

    test('игнорирует регистр и повторяющиеся пробелы', () {
      final rows = [
        _row(
          1,
          nomenclature: '  МОНИТОР   24 ',
          characteristic: ' BLACK ',
        ),
      ];

      final result = BarcodeMatcher().matchByNomenclatureCharacteristic(
        'монитор 24',
        'black',
        rows,
      );

      expect(result.isUnique, true);
    });
  });
}
