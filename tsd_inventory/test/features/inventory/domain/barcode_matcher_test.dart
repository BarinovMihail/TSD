import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

DocTableRow _row(int line, String code,
        {String inv = '', String series = '', String nom = ''}) =>
    DocTableRow(
      lineNumber: line,
      inventoryNumber: inv,
      nomenclature: nom,
      nomenclatureCode: code,
      characteristic: '',
      series: series,
      seriesStatus: '0',
      fio: '',
      qtyAccounting: 1,
      qtyActual: 0,
      action: '',
    );

void main() {
  test('уникальное совпадение по НоменклатураКод', () {
    final rows = [_row(1, '000123'), _row(2, '000456')];
    final r = BarcodeMatcher().match('000123', rows);
    expect(r.isUnique, true);
    expect(r.exact.single.lineNumber, 1);
  });

  test('несколько совпадений → ambiguous', () {
    final rows = [_row(1, '000123'), _row(2, '000123')];
    final r = BarcodeMatcher().match('000123', rows);
    expect(r.isAmbiguous, true);
    expect(r.exact.length, 2);
  });

  test('нет совпадений → none', () {
    final rows = [_row(1, '000123')];
    expect(BarcodeMatcher().match('999', rows).isNone, true);
  });

  test('пустой код → none', () {
    final rows = [_row(1, '000123')];
    expect(BarcodeMatcher().match('   ', rows).isNone, true);
  });

  test('fallback на ИнвентарныйНомер ТОЛЬКО если НоменклатураКод пуст у всех', () {
    final rows = [_row(1, '', inv: '44182'), _row(2, '', inv: '44183')];
    final r = BarcodeMatcher().match('44182', rows);
    expect(r.isUnique, true);
    expect(r.exact.single.lineNumber, 1);
  });

  test('fallback НЕ срабатывает, если хотя бы у одной строки есть НоменклатураКод',
      () {
    final rows = [_row(1, '000123'), _row(2, '', inv: '44183')];
    final r = BarcodeMatcher().match('44183', rows);
    expect(r.isNone, true); // fallback отключён, т.к. есть строка с кодом
  });

  test('fallback на Серию когда все коды пусты', () {
    final rows = [_row(1, '', series: 'SR-1'), _row(2, '', series: 'SR-2')];
    final r = BarcodeMatcher().match('SR-2', rows);
    expect(r.isUnique, true);
    expect(r.exact.single.lineNumber, 2);
  });

  test('normalize: trim пробелов', () {
    final rows = [_row(1, '000123')];
    expect(BarcodeMatcher().match('  000123  ', rows).isUnique, true);
  });

  test('восклицательные знаки в отсканированном коде заменяются на пробел', () {
    // Сканер шлёт «618810!!!!!!»; в 1С код хранится без добивки.
    final rows = [_row(1, '618810'), _row(2, '000456')];
    expect(BarcodeMatcher().match('618810!!!!!!', rows).isUnique, true);
    expect(BarcodeMatcher().match('618810!!!!!!', rows).exact.single.lineNumber,
        1);
  });

  test('trailing-пробелы игнорируются при сравнении', () {
    // Отсканировано с добивкой, в 1С — без неё (и наоборот).
    final rows = [_row(1, '000123')];
    expect(
        BarcodeMatcher().match('000123      ', rows).isUnique, true); // скан
    final rows2 = [_row(1, '000123      ')]; // 1С с фиксированной шириной
    expect(BarcodeMatcher().match('000123', rows2).isUnique, true);
  });
}
