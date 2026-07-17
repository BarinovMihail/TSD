/// Строка табличной части документа из /code/.
class DocTableRow {
  DocTableRow({
    required this.lineNumber,
    required this.inventoryNumber,
    required this.nomenclature,
    required this.nomenclatureCode,
    required this.characteristic,
    required this.series,
    required this.seriesStatus,
    required this.fio,
    required this.qtyAccounting,
    required this.qtyActual,
    required this.action,
    List<String> barcodes = const [],
  }) : barcodes = List<String>.unmodifiable(barcodes);

  final int lineNumber; // ключ "1","2" → int
  final String inventoryNumber; // "44182" или ""
  final String nomenclature; // человекочитаемый текст
  final String nomenclatureCode; // НоменклатураКод
  final String characteristic;
  final String series;
  final String seriesStatus; // "0"..
  final String fio; // ФизическоеЛицо (текст)
  final int qtyAccounting; // из строки через int.tryParse
  final int qtyActual; // из строки через int.tryParse
  final String action; // Действие (расхождения)

  /// Штрихкоды позиции из свойства «Штрихкоды». Как строки: ведущие нули
  /// сохраняются, пустые значения отброшены парсером. Несколько штрихкодов
  /// возможны — совпадение с любым из них отмечает позицию.
  final List<String> barcodes;

  /// Есть ли у позиции один или несколько штрихкодов (состояние иконки).
  bool get hasBarcodes => barcodes.isNotEmpty;

  bool get isFound => qtyActual > 0;
  bool get hasDiscrepancy => qtyActual != qtyAccounting;

  /// copyWith сохраняет barcodes. Параметр [barcodes] необязателен —
  /// используется при перезагрузке документа, чтобы заменить массивы
  /// свежими данными с сервера.
  DocTableRow copyWith({
    int? qtyActual,
    String? action,
    List<String>? barcodes,
  }) => DocTableRow(
    lineNumber: lineNumber,
    inventoryNumber: inventoryNumber,
    nomenclature: nomenclature,
    nomenclatureCode: nomenclatureCode,
    characteristic: characteristic,
    series: series,
    seriesStatus: seriesStatus,
    fio: fio,
    qtyAccounting: qtyAccounting,
    qtyActual: qtyActual ?? this.qtyActual,
    action: action ?? this.action,
    barcodes: barcodes ?? this.barcodes,
  );
}
