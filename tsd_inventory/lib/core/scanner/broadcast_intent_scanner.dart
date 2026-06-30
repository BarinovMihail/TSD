import 'dart:async';

import 'scanner_source.dart';

/// Приём скан-кодов через Broadcast Intent от M3 Mobile SDK.
///
/// TODO(M3 SDK): для подключения потребуется AAR M3 Mobile SDK и
/// Android-нативная обвязка (EventChannel/BroadcastReceiver). Сейчас — stub.
/// Включается через AppConfig.scannerMode == ScannerMode.broadcastIntent.
class BroadcastIntentScanner implements ScannerSource {
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get codes => _controller.stream;

  @override
  Future<void> start() async {
    // TODO(M3 SDK): зарегистрировать BroadcastReceiver, слушать Intent,
    // парсить extras и пушить в _controller.add(code).
    throw UnimplementedError(
        'BroadcastIntentScanner требует M3 Mobile SDK (не подключён)');
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
