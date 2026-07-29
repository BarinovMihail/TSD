import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/feedback/feedback_service.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/application/inventory_screen_controller.dart';
import 'package:tsd_inventory/features/inventory/application/scan_controller.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_assignment.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';
import 'package:tsd_inventory/features/inventory/presentation/unknown_barcode_dialog.dart';
import 'package:tsd_inventory/l10n/app_strings.dart';

class _MockRepo extends Mock implements InventoryRepository {}

class _MockDb extends Mock implements AppDatabase {}

class _MockFeedback extends Mock implements FeedbackService {}

DocTableRow _row({
  int lineNumber = 1,
  String nomenclature = 'Монитор',
  String nomenclatureCode = '001',
  String characteristic = '',
  int qtyActual = 0,
}) => DocTableRow(
  lineNumber: lineNumber,
  inventoryNumber: '',
  nomenclature: nomenclature,
  nomenclatureCode: nomenclatureCode,
  characteristic: characteristic,
  series: '',
  seriesStatus: '0',
  fio: '',
  qtyAccounting: 1,
  qtyActual: qtyActual,
  action: '',
);

InventoryScreenController _controller(
  _MockRepo repo,
  _MockDb db,
  _MockFeedback feedback,
) {
  final controller = InventoryScreenController(
    docCode: 'АЕ-1',
    repo: repo,
    db: db,
    matcher: BarcodeMatcher(),
    feedback: feedback,
  );
  controller.scan = ScanController(
    docCode: 'АЕ-1',
    initialRows: [_row()],
    repo: repo,
    db: db,
    matcher: BarcodeMatcher(),
    feedback: feedback,
  );
  controller.loading = false;
  return controller;
}

void main() {
  late _MockRepo repo;
  late _MockDb db;
  late _MockFeedback feedback;

  setUp(() {
    repo = _MockRepo();
    db = _MockDb();
    feedback = _MockFeedback();
    registerFallbackValue('');
    when(() => feedback.success()).thenAnswer((_) async {});
    when(
      () => db.getScanProgress(any()),
    ).thenAnswer((_) async => <int, ScanProgressData>{});
    when(
      () => db.upsertScanProgress(
        docCode: any(named: 'docCode'),
        lineNo: any(named: 'lineNo'),
        nomenclatureCode: any(named: 'nomenclatureCode'),
        qtyActual: any(named: 'qtyActual'),
        action: any(named: 'action'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => repo.getBarcodeAssignment(any()),
    ).thenAnswer((_) async => const Success(null));
    when(
      () => repo.addScannedBarcode(any(), any(), any()),
    ).thenAnswer((_) async => const Success(null));
    when(
      () => repo.addNewLine(any(), any(), any()),
    ).thenAnswer((_) async => const Success(null));
    when(
      () => repo.getTable(any()),
    ).thenAnswer(
      (_) async => Success([
        _row(
          lineNumber: 2,
          nomenclature: 'Клавиатура',
          characteristic: '',
          qtyActual: 1,
        ),
      ]),
    );
  });

  Widget wrap(InventoryScreenController controller) => MaterialApp(
    home: Scaffold(
      body: UnknownBarcodeDialog(barcode: '460123', ctrl: controller),
    ),
  );

  testWidgets('выбор номенклатуры загружает и требует характеристику', (
    tester,
  ) async {
    when(
      () => repo.getNomenclatures(),
    ).thenAnswer((_) async => const Success(['Клавиатура', 'Монитор']));
    when(
      () => repo.getCharacteristics('Клавиатура'),
    ).thenAnswer((_) async => const Success(['Белая', 'Чёрная']));
    when(
      () => repo.getTable(any()),
    ).thenAnswer(
      (_) async => Success([
        _row(
          lineNumber: 2,
          nomenclature: 'Клавиатура',
          characteristic: 'Белая',
        ),
      ]),
    );
    final controller = _controller(repo, db, feedback);

    await tester.pumpWidget(wrap(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Клавиатура'));
    await tester.pumpAndSettle();

    expect(find.text('Белая'), findsOneWidget);
    expect(find.text('Чёрная'), findsOneWidget);
    final assignButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.assignBarcode),
    );
    expect(assignButton.onPressed, isNull);

    await tester.tap(find.text('Белая'));
    await tester.pump();
    await tester.tap(find.text(AppStrings.assignBarcode));
    await tester.pumpAndSettle();

    verify(
      () => repo.addScannedBarcode('Клавиатура', 'Белая', '460123'),
    ).called(1);
    verify(
      () => repo.addNewLine('АЕ-1', 'Клавиатура', 'Белая'),
    ).called(1);
  });

  testWidgets('без характеристик отправляет пустую характеристику', (
    tester,
  ) async {
    when(
      () => repo.getNomenclatures(),
    ).thenAnswer((_) async => const Success(['Клавиатура']));
    when(
      () => repo.getCharacteristics('Клавиатура'),
    ).thenAnswer((_) async => const Success([]));
    final controller = _controller(repo, db, feedback);

    await tester.pumpWidget(wrap(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Клавиатура'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.withoutCharacteristic), findsOneWidget);
    await tester.tap(find.text(AppStrings.assignBarcode));
    await tester.pumpAndSettle();

    verify(
      () => repo.addScannedBarcode('Клавиатура', '', '460123'),
    ).called(1);
    verify(
      () => repo.addNewLine('АЕ-1', 'Клавиатура', ''),
    ).called(1);
  });

  testWidgets('характеристика «-» выбирается как реальная, а не пустая', (
    tester,
  ) async {
    when(
      () => repo.getNomenclatures(),
    ).thenAnswer(
      (_) async => const Success(['015.020.063.00052 Седло']),
    );
    when(
      () => repo.getCharacteristics('015.020.063.00052 Седло'),
    ).thenAnswer((_) async => const Success(['-']));
    when(
      () => repo.getTable(any()),
    ).thenAnswer(
      (_) async => Success([
        _row(
          lineNumber: 2,
          nomenclature: 'Седло',
          nomenclatureCode: '015.020.063.00052',
          characteristic: '-',
        ),
      ]),
    );
    final controller = _controller(repo, db, feedback);

    await tester.pumpWidget(wrap(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('015.020.063.00052 Седло'));
    await tester.pumpAndSettle();

    expect(find.text('-'), findsOneWidget);
    expect(find.text(AppStrings.withoutCharacteristic), findsNothing);
    await tester.tap(find.text(AppStrings.assignBarcode));
    await tester.pumpAndSettle();

    verify(
      () => repo.addScannedBarcode(
        '015.020.063.00052 Седло',
        '-',
        '460123',
      ),
    ).called(1);
    verify(
      () => repo.addNewLine('АЕ-1', '015.020.063.00052 Седло', '-'),
    ).called(1);
  });

  testWidgets(
    'повторная попытка завершает /newStr, если ШК уже успел записаться',
    (tester) async {
      when(
        () => repo.getNomenclatures(),
      ).thenAnswer((_) async => const Success(['Клавиатура']));
      when(
        () => repo.getCharacteristics('Клавиатура'),
      ).thenAnswer((_) async => const Success([]));
      when(() => repo.getBarcodeAssignment('460123')).thenAnswer(
        (_) async => const Success(
          BarcodeAssignment(
            nomenclature: 'Клавиатура',
            characteristic: '',
          ),
        ),
      );
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(ServerError(code: 500)));
      final controller = _controller(repo, db, feedback);

      await tester.pumpWidget(wrap(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Клавиатура'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.assignBarcode));
      await tester.pumpAndSettle();

      verify(
        () => repo.addNewLine('АЕ-1', 'Клавиатура', ''),
      ).called(1);
    },
  );
}
