/// Строка табличной части документа из /code/.
class DocTableRow {
  const DocTableRow({
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
  });

  final int lineNumber; // ключ "1","2" → int
  final String inventoryNumber; // "44182" или ""
  final String nomenclature; // человекочитаемый текст
  final String nomenclatureCode; // НоменклатураКод — КЛЮЧ матчера
  final String characteristic;
  final String series;
  final String seriesStatus; // "0"..
  final String fio; // ФизическоеЛицо (текст)
  final int qtyAccounting; // из строки через int.tryParse
  final int qtyActual; // из строки через int.tryParse
  final String action; // Действие (расхождения)

  bool get isFound => qtyActual > 0;
  bool get hasDiscrepancy => qtyActual != qtyAccounting;

  DocTableRow copyWith({int? qtyActual, String? action}) => DocTableRow(
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
      );
}
