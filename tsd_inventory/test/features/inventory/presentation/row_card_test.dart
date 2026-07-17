import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';
import 'package:tsd_inventory/features/inventory/presentation/row_card.dart';

DocTableRow _row({List<String> barcodes = const []}) => DocTableRow(
  lineNumber: 1,
  inventoryNumber: '44182',
  nomenclature: 'Монитор',
  nomenclatureCode: '00-00000123',
  characteristic: 'Black',
  series: '',
  seriesStatus: '0',
  fio: '',
  qtyAccounting: 1,
  qtyActual: 0,
  action: '',
  barcodes: barcodes,
);

/// Корректный 1x1 RGBA PNG (transparent) — сами иконки-ассеты.
final Uint8List _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// AssetBundle, отдающий PNG для иконок и валидный пустой манифест для
/// служебных ключей, чтобы Image.asset в RowCard декодировался в тестах
/// без реальных файлов ассетов.
class _FakeBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      // standard-message-codec: пустая карта { }.
      return ByteData.sublistView(
        const StandardMessageCodec().encodeMessage(<Object, Object>{})!,
      );
    }
    if (key == 'AssetManifest.json' || key == 'FontManifest.json') {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode('{}')));
    }
    return ByteData.sublistView(_png);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'AssetManifest.json' || key == 'FontManifest.json') return '{}';
    return utf8.decode(_png);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => DefaultAssetBundle(
    bundle: _FakeBundle(),
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('нет штрихкодов → иконка barcode_missing и колбэк по тапу', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        RowCard(
          row: _row(barcodes: const []),
          onTapBarcode: () => tapped = true,
        ),
      ),
    );
    // Прокачиваем async-декодирование изображения до конца.
    await tester.pumpAndSettle();

    final img = tester.widget<Image>(find.byType(Image));
    expect(
      (img.image as AssetImage).assetName,
      'assets/icons/barcode_missing.png',
    );
    await tester.tap(find.byType(IconButton));
    expect(tapped, true);
  });

  testWidgets('есть штрихкоды → иконка barcode_available', (tester) async {
    await tester.pumpWidget(
      wrap(
        RowCard(
          row: _row(barcodes: const ['111', '222']),
          onTapBarcode: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final img = tester.widget<Image>(find.byType(Image));
    expect(
      (img.image as AssetImage).assetName,
      'assets/icons/barcode_available.png',
    );
  });

  testWidgets('onTapBarcode=null → иконка не показывается', (tester) async {
    await tester.pumpWidget(wrap(RowCard(row: _row(barcodes: const ['111']))));
    await tester.pump();
    expect(find.byType(IconButton), findsNothing);
  });
}
