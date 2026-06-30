/// Документ инвентаризации из списка /fio/.
class DocListItem {
  const DocListItem({
    required this.ref,
    required this.number,
    required this.date,
    required this.posted,
    this.organizationGuid,
    this.departmentGuid,
    this.responsibleGuid,
  });

  final String ref; // GUID
  final String number; // "АЕ-00000002"
  final DateTime date;
  final bool posted;
  final String? organizationGuid; // GUID (человекочитаемого в /fio/ нет)
  final String? departmentGuid;
  final String? responsibleGuid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocListItem &&
          runtimeType == other.runtimeType &&
          ref == other.ref;

  @override
  int get hashCode => ref.hashCode;
}
