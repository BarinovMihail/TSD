/// Документ инвентаризации из списка /fio/.
class DocListItem {
  const DocListItem({
    required this.number,
    required this.date,
    this.department,
    this.posted = false,
  });

  final String number; // "АЕ-00000002" (НомерДок)
  final DateTime date;
  final String? department; // "Отдел закупок" (Подразделение)
  final bool posted; // флаг проведения, если сервер его вернёт (иначе false)

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocListItem &&
          runtimeType == other.runtimeType &&
          number == other.number;

  @override
  int get hashCode => number.hashCode;
}
