import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/scanner/keyboard_wedge_scanner.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';
import 'package:tsd_inventory/features/inventory/presentation/inventory_screen.dart';

DocTableRow _row() => DocTableRow(
  lineNumber: 1,
  inventoryNumber: '',
  nomenclature: 'Клавиатура',
  nomenclatureCode: '001',
  characteristic: 'Белая',
  series: '',
  seriesStatus: '0',
  fio: '',
  qtyAccounting: 1,
  qtyActual: 0,
  action: '',
);

void main() {
  testWidgets('окно привязки само принимает keyboard-wedge скан', (
    tester,
  ) async {
    final scanner = KeyboardWedgeScanner(
      flushTimeout: const Duration(seconds: 1),
    );
    final codeCompleter = Completer<String>();
    String? captured;
    final subscription = scanner.codes.listen((code) {
      captured = code;
      if (!codeCompleter.isCompleted) codeCompleter.complete(code);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => BarcodeCaptureDialog(
                  row: _row(),
                  codeFuture: codeCompleter.future,
                  scanner: scanner,
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(captured, '123');

    await subscription.cancel();
    await scanner.dispose();
  });
}
