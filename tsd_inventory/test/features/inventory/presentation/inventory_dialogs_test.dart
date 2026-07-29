import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/presentation/inventory_dialogs.dart';
import 'package:tsd_inventory/l10n/app_strings.dart';

void main() {
  testWidgets('неизвестный ШК: Создать сверху, Отмена снизу и во всю ширину', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnknownBarcodePromptDialog(barcode: '4601234567890'),
        ),
      ),
    );

    final create = find.widgetWithText(
      FilledButton,
      AppStrings.createNomenclatureFromBarcode,
    );
    final cancel = find.widgetWithText(OutlinedButton, AppStrings.cancel);
    expect(create, findsOneWidget);
    expect(cancel, findsOneWidget);

    final createRect = tester.getRect(create);
    final cancelRect = tester.getRect(cancel);
    expect(createRect.top, lessThan(cancelRect.top));
    expect(createRect.width, closeTo(cancelRect.width, 0.1));
    expect(createRect.height, 56);
    expect(cancelRect.height, 56);
  });
}
