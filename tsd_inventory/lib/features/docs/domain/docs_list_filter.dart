import 'doc_list_item.dart';

enum DocsSortOrder { newestFirst, oldestFirst }

/// Возвращает новый список документов, отфильтрованный по номеру и
/// отсортированный по дате. Исходный список контроллера не изменяется.
List<DocListItem> filterAndSortDocs(
  Iterable<DocListItem> docs, {
  required String query,
  required DocsSortOrder sortOrder,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final result = docs
      .where(
        (doc) =>
            normalizedQuery.isEmpty ||
            doc.number.toLowerCase().contains(normalizedQuery),
      )
      .toList();

  result.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) {
      return sortOrder == DocsSortOrder.newestFirst ? -byDate : byDate;
    }
    return a.number.compareTo(b.number);
  });
  return result;
}
