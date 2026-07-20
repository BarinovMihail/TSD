import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/docs/domain/doc_list_item.dart';
import 'package:tsd_inventory/features/docs/domain/docs_list_filter.dart';

DocListItem _doc(String number, DateTime date) => DocListItem(
  number: number,
  date: date,
);

void main() {
  final docs = [
    _doc('АЕ-00000002', DateTime(2026, 7, 2)),
    _doc('АЕ-00000001', DateTime(2026, 7, 1)),
    _doc('БП-00000003', DateTime(2026, 7, 3)),
  ];

  test('поиск фильтрует документы по части номера без учёта регистра', () {
    final result = filterAndSortDocs(
      docs,
      query: ' ае-0000000 ',
      sortOrder: DocsSortOrder.newestFirst,
    );

    expect(result.map((doc) => doc.number), [
      'АЕ-00000002',
      'АЕ-00000001',
    ]);
  });

  test('по умолчанию можно показать новые документы первыми', () {
    final result = filterAndSortDocs(
      docs,
      query: '',
      sortOrder: DocsSortOrder.newestFirst,
    );

    expect(result.map((doc) => doc.number), [
      'БП-00000003',
      'АЕ-00000002',
      'АЕ-00000001',
    ]);
  });

  test('сортировка может показать старые документы первыми', () {
    final result = filterAndSortDocs(
      docs,
      query: '',
      sortOrder: DocsSortOrder.oldestFirst,
    );

    expect(result.map((doc) => doc.number), [
      'АЕ-00000001',
      'АЕ-00000002',
      'БП-00000003',
    ]);
  });
}
