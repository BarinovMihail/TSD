import 'dart:async';

import 'scanner_source.dart';

/// Приём скан-кодов как keyboard wedge: скрытый TextField + onSubmitted.
/// Буферизует быстрый ввод (устройства шлют код порциями) с таймаутом ~80мс.
///
/// Виджет-обёртка, держащая фокус, реализован в [KeyboardWedgeField]
/// (см. inventory_screen.dart, Task 18). Этот класс отвечает за логику склейки.
class KeyboardWedgeScanner implements ScannerSource {
  final _controller = StreamController<String>.broadcast();
  final _buf = StringBuffer();
  Timer? _idleTimer;

  /// Таймаут завершения порции ввода (мс).
  final Duration flushTimeout;

  KeyboardWedgeScanner({this.flushTimeout = const Duration(milliseconds: 80)});

  @override
  Stream<String> get codes => _controller.stream;

  /// Вызывается из onChanged скрытого поля: накапливает символы.
  void onTextChanged(String chunk) {
    _buf.write(chunk);
    _idleTimer?.cancel();
    _idleTimer = Timer(flushTimeout, _flush);
  }

  /// Вызывается из onSubmitted (Enter от сканера) — основной путь.
  void onSubmitted(String value) {
    _buf.write(value);
    _flush();
  }

  void _flush() {
    _idleTimer?.cancel();
    final code = _buf.toString().trim();
    _buf.clear();
    if (code.isNotEmpty) {
      _controller.add(code);
    }
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    _idleTimer?.cancel();
    await _controller.close();
  }
}
