/// Данные номенклатуры, полученные из регистра сведений по штрихкоду.
/// Ответ плоского эндпоинта GET /hs/inventory/barcode/{Код}:
///   { "Номенклатура": "Монитор", "Характеристика": "23,5\" Samsung №…" }
/// Если штрихкод не зарегистрирован в 1С, эндпоинт возвращает пустой объект {}
/// — это кодируется как [BarcodeInfo] с пустыми полями / null в репозитории.
class BarcodeInfo {
  const BarcodeInfo({required this.nomenclature, required this.characteristic});

  final String nomenclature;
  final String characteristic;

  /// Штрихкод не зарегистрирован в 1С (пустой ответ {}).
  bool get isEmpty => nomenclature.trim().isEmpty && characteristic.trim().isEmpty;
}
