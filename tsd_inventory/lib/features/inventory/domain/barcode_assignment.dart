/// Текущая позиция, к которой в 1С привязан штрихкод.
class BarcodeAssignment {
  const BarcodeAssignment({
    required this.nomenclature,
    required this.characteristic,
  });

  final String nomenclature;
  final String characteristic;

  bool matches({
    required String nomenclature,
    required String characteristic,
  }) =>
      this.nomenclature.trim() == nomenclature.trim() &&
      this.characteristic.trim() == characteristic.trim();
}
