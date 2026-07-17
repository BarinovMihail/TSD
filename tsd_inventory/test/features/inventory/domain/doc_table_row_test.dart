import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

DocTableRow _row({
  required int accounting,
  required int actual,
  List<String> barcodes = const [],
}) => DocTableRow(
  lineNumber: 1,
  inventoryNumber: '',
  nomenclature: '',
  nomenclatureCode: '',
  characteristic: '',
  series: '',
  seriesStatus: '0',
  fio: '',
  qtyAccounting: accounting,
  qtyActual: actual,
  action: '',
  barcodes: barcodes,
);

void main() {
  test('факт 0 → не найдено', () {
    expect(_row(accounting: 1, actual: 0).isFound, false);
  });
  test('факт > 0 и == учёту → найдено без расхождения', () {
    final r = _row(accounting: 2, actual: 2);
    expect(r.isFound, true);
    expect(r.hasDiscrepancy, false);
  });
  test('факт ≠ учёту → расхождение', () {
    final r = _row(accounting: 3, actual: 1);
    expect(r.isFound, true);
    expect(r.hasDiscrepancy, true);
  });

  group('Штрихкоды', () {
    test('есть штрихкоды → hasBarcodes=true', () {
      expect(
        _row(accounting: 1, actual: 0, barcodes: ['111']).hasBarcodes,
        true,
      );
    });
    test('нет штрихкодов → hasBarcodes=false', () {
      expect(_row(accounting: 1, actual: 0, barcodes: []).hasBarcodes, false);
    });
    test('несколько штрихкодов сохраняются', () {
      final r = _row(accounting: 1, actual: 0, barcodes: ['111', '222']);
      expect(r.barcodes, ['111', '222']);
      expect(r.hasBarcodes, true);
    });
    test('copyWith сохраняет barcodes', () {
      final r = _row(accounting: 1, actual: 0, barcodes: ['111']);
      final updated = r.copyWith(qtyActual: 1);
      expect(updated.barcodes, ['111']);
    });
    test('copyWith может заменить barcodes', () {
      final r = _row(accounting: 1, actual: 0, barcodes: ['111']);
      final updated = r.copyWith(barcodes: ['111', '222']);
      expect(updated.barcodes, ['111', '222']);
    });
  });
}
