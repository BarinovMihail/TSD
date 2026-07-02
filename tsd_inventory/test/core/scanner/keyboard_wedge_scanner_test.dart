import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/scanner/keyboard_wedge_scanner.dart';

/// Тесты keyboard wedge на СЫРЫХ KeyEvent. Логика накопления (acceptChar/
/// acceptSubmit) отделена от конструирования KeyEvent и тестируется напрямую —
/// это и есть защита от регрессии фрагментации кода («00-0», «00-000-00»).
void main() {
  late KeyboardWedgeScanner scanner;
  late List<String> emitted;

  setUp(() {
    scanner = KeyboardWedgeScanner();
    emitted = [];
    scanner.codes.listen(emitted.add);
  });

  tearDown(() => scanner.dispose());

  Future<void> pumpMicrotasks() => Future<void>.delayed(Duration.zero);

  test('серия символов + Enter → один полный код', () async {
    for (final c in '00-00014053'.split('')) {
      scanner.acceptChar(c);
    }
    scanner.acceptSubmit();
    await pumpMicrotasks();
    expect(emitted, ['00-00014053']);
  });

  test('Enter без данных — ничего не эмитится', () async {
    scanner.acceptSubmit();
    await pumpMicrotasks();
    expect(emitted, isEmpty);
  });

  test('каждый символ накапливается ровно один раз (нет дублирования)', () async {
    // Регрессия: раньше onChanged дописывал полный снимок поля → дубли цифр.
    scanner.acceptChar('0');
    scanner.acceptChar('0');
    scanner.acceptChar('-');
    scanner.acceptChar('1');
    scanner.acceptSubmit();
    await pumpMicrotasks();
    expect(emitted, ['00-1']);
  });

  test('несколько подряд сканирований разделяются по Enter', () async {
    for (final c in '111'.split('')) {
      scanner.acceptChar(c);
    }
    scanner.acceptSubmit();
    for (final c in '222'.split('')) {
      scanner.acceptChar(c);
    }
    scanner.acceptSubmit();
    await pumpMicrotasks();
    expect(emitted, ['111', '222']);
  });

  test('fallback: flush по idle-таймауту без Enter', () async {
    final fast = KeyboardWedgeScanner(
        flushTimeout: const Duration(milliseconds: 30));
    final got = <String>[];
    fast.codes.listen(got.add);
    fast.acceptChar('1');
    fast.acceptChar('2');
    fast.acceptChar('3');
    await Future.delayed(const Duration(milliseconds: 120));
    expect(got, ['123']);
    await fast.dispose();
  });

  test('восклицательный знак заменяется пробелом («!» → « »)', () async {
    // «618810!!!!!!» → буфер содержит «618810      », после trim → «618810».
    for (final c in '618810!!!!!!'.split('')) {
      scanner.acceptChar(c);
    }
    scanner.acceptSubmit();
    await pumpMicrotasks();
    expect(emitted, ['618810']);
  });
}
