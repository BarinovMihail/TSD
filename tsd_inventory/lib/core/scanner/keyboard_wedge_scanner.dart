import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'scanner_source.dart';

/// Приём скан-кодов как keyboard wedge через СЫРЫЕ [KeyEvent] (Focus.onKeyEvent).
///
/// Раньше использовался скрытый TextField + onChanged/onSubmitted, но при
/// мгновенной посылке сканера (interval = 0) колбэки TextField приходят в
/// перемешанном порядке и значение фрагментируется («00-0», «00-000-00» и т.п.),
/// а поле ещё и поднимает soft-keyboard (Gboard). Сырые KeyEvent лишены этих
/// проблем: одно нажатие — один символ, Enter/CR — завершение кода.
///
/// Логика накопления вынесена в [acceptChar]/[acceptSubmit] (тестируется без
/// конструирования KeyEvent); [handleKeyEvent] — адаптер к Focus.onKeyEvent.
class KeyboardWedgeScanner implements ScannerSource {
  final _controller = StreamController<String>.broadcast();
  final _buf = StringBuffer();
  Timer? _idleTimer;

  /// Таймаут отправки (fallback), если сканер НЕ шлёт Enter как End character.
  final Duration flushTimeout;

  KeyboardWedgeScanner({this.flushTimeout = const Duration(milliseconds: 100)});

  @override
  Stream<String> get codes => _controller.stream;

  /// Накопить печатный символ (из KeyEvent.character).
  /// Восклицательный знак заменяется пробелом: некоторые сканеры шлют
  /// добивку из «!» вместо пробелов («618810!!!!!!» → «618810     »).
  void acceptChar(String char) {
    _buf.write(char == '!' ? ' ' : char);
    _idleTimer?.cancel();
    _idleTimer = Timer(flushTimeout, _flush);
  }

  /// Завершить и отправить накопленный код (Enter / CR от сканера).
  void acceptSubmit() => _flush();

  /// Обработчик сырых KeyEvent — вешается на Focus.onKeyEvent.
  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    // Завершение кода: Enter (сканер с End character = keyboard Enter).
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      acceptSubmit();
      return KeyEventResult.handled;
    }
    var c = event.character;
    if (c == null || c == '\u0000') c = _charFromLogical(key);
    if (c == null || c.isEmpty) return KeyEventResult.skipRemainingHandlers;
    // CR/LF тоже трактуем как завершение (некоторые сканеры шлют \r).
    if (c == '\n' || c == '\r') {
      acceptSubmit();
      return KeyEventResult.handled;
    }
    acceptChar(c);
    return KeyEventResult.handled;
  }

  /// Fallback: символ из logicalKey, если character == null (на некоторых
  /// Android keyLabel односимвольный для цифр/минуса/букв).
  String? _charFromLogical(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    return (label.length == 1) ? label : null;
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
