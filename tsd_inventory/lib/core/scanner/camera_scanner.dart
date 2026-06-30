import 'dart:async';

import 'scanner_source.dart';

/// Камерный сканер (mobile_scanner). Резерв/ручной режим.
/// Виджет камеры открывается по кнопке «Сканировать камерой» на экране ТЧ.
/// Здесь — обёртка потока; сам виджет mobile_scanner используется напрямую в UI.
class CameraScanner implements ScannerSource {
  final _controller = StreamController<String>.broadcast();

  /// UI mobile_scanner вызывает этот метод при декоде кода.
  void onDecoded(String code) {
    if (code.isNotEmpty) _controller.add(code);
  }

  @override
  Stream<String> get codes => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
