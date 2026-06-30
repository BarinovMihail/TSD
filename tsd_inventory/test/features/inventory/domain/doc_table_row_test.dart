import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

DocTableRow _row({required int accounting, required int actual}) => DocTableRow(
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
}
