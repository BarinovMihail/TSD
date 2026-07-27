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
    String nomenclatureCode = '',
  }) =>
      nomenclatureValuesMatch(
        this.nomenclature,
        nomenclature,
        nomenclatureCode: nomenclatureCode,
      ) &&
      normalizeInventoryText(this.characteristic) ==
          normalizeInventoryText(characteristic);
}

/// HTTP-сервисы 1С возвращают одну номенклатуру в двух представлениях:
/// «015.020.063.00052 Седло» в каталоге/регистре и «Седло» +
/// «015.020.063.00052» отдельным кодом в строке документа.
bool nomenclatureValuesMatch(
  String left,
  String right, {
  String nomenclatureCode = '',
}) {
  final normalizedLeft = normalizeInventoryText(left);
  final normalizedRight = normalizeInventoryText(right);
  if (normalizedLeft == normalizedRight) return true;

  final normalizedCode = normalizeInventoryText(nomenclatureCode);
  if (normalizedCode.isNotEmpty) {
    return normalizedLeft == '$normalizedCode $normalizedRight' ||
        normalizedRight == '$normalizedCode $normalizedLeft';
  }

  // В некоторых ответах код есть только внутри строки каталога, отдельного
  // поля с кодом рядом нет.
  final leftWithoutCode = _withoutLeadingNomenclatureCode(normalizedLeft);
  final rightWithoutCode = _withoutLeadingNomenclatureCode(normalizedRight);
  return leftWithoutCode == normalizedRight ||
      rightWithoutCode == normalizedLeft;
}

String normalizeInventoryText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String _withoutLeadingNomenclatureCode(String value) {
  final separator = value.indexOf(' ');
  if (separator <= 0) return value;
  final prefix = value.substring(0, separator);
  if (!RegExp(r'^[0-9][0-9._/-]*$').hasMatch(prefix)) return value;
  return value.substring(separator + 1).trim();
}
