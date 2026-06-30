/// Единый интерфейс приёма штрихкодов.
/// UI и ScanController зависят только от него — смена стратегии = замена реализации.
abstract interface class ScannerSource {
  /// Поток отсканированных кодов (уже «склеенных», по одной строке на скан).
  Stream<String> get codes;

  /// Запуск (подписка на источник устройства/SDK).
  Future<void> start();

  /// Освобождение ресурсов.
  Future<void> dispose();
}
