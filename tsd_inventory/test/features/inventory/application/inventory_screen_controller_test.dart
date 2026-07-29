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

class _MockRepo extends Mock implements InventoryRepository {}

class _MockDb extends Mock implements AppDatabase {}

class _MockFeedback extends Mock implements FeedbackService {}

DocTableRow _row({
  int lineNumber = 1,
  String nomenclature = 'Монитор',
  String nomenclatureCode = '00-00000123',
  String characteristic = 'Black',
  List<String> barcodes = const [],
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
  barcodes: barcodes,
);

InventoryScreenController _controller(
  _MockRepo repo,
  _MockDb db,
  _MockFeedback feedback,
  DocTableRow row,
) {
  final c = InventoryScreenController(
    docCode: 'АЕ-1',
    repo: repo,
    db: db,
    matcher: BarcodeMatcher(),
    feedback: feedback,
  );
  c.scan = ScanController(
    docCode: 'АЕ-1',
    initialRows: [row],
    repo: repo,
    db: db,
    matcher: BarcodeMatcher(),
    feedback: feedback,
  );
  c.loading = false;
  return c;
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
    when(() => db.getScanProgress(any())).thenAnswer((_) async => <int, ScanProgressData>{});
    when(
      () => db.upsertScanProgress(
        docCode: any(named: 'docCode'),
        lineNo: any(named: 'lineNo'),
        nomenclatureCode: any(named: 'nomenclatureCode'),
        qtyActual: any(named: 'qtyActual'),
        action: any(named: 'action'),
      ),
    ).thenAnswer((_) async {});
    when(() => db.deleteScanProgressLine(any(), any())).thenAnswer((_) async {});
    when(() => repo.getBarcodeAssignment(any())).thenAnswer((_) async => const Success(null));
  });

  test('reload сохраняет серверный факт при локальной записи с нулём', () async {
    when(() => repo.getTable('АЕ-1')).thenAnswer((_) async => Success([_row(qtyActual: 3)]));
    when(() => db.getScanProgress('АЕ-1')).thenAnswer(
      (_) async => {
        1: ScanProgressData(
          docCode: 'АЕ-1',
          lineNumber: 1,
          nomenclatureCode: '00-00000123',
          qtyActual: 0,
          action: '',
          updatedAt: DateTime(2026),
        ),
      },
    );
    final ctrl = _controller(repo, db, feedback, _row());

    final result = await ctrl.reload();

    expect(result, isA<Success>());
    expect(ctrl.scan!.rows.single.qtyActual, 3);
  });

  group('visibleRows', () {
    test('применяет поиск и не меняет исходный порядок строк', () {
      final ctrl = _controller(repo, db, feedback, _row());
      ctrl.scan!.replaceRows([
        _row(lineNumber: 3, nomenclature: 'Клавиатура'),
        _row(lineNumber: 1, nomenclature: 'Монитор'),
        _row(lineNumber: 2, nomenclature: 'Принтер'),
      ]);
      ctrl.searchQuery = 'МОНИ';

      expect(ctrl.visibleRows.map((row) => row.lineNumber), [1]);
      expect(ctrl.scan!.rows.map((row) => row.lineNumber), [3, 1, 2]);
    });

    test('фильтрует строки без штрихкода', () {
      final ctrl = _controller(repo, db, feedback, _row());
      ctrl.scan!.replaceRows([
        _row(lineNumber: 1, barcodes: const ['111']),
        _row(lineNumber: 2),
      ]);
      ctrl.onlyWithoutBarcode = true;

      expect(ctrl.visibleRows.map((row) => row.lineNumber), [2]);
    });

    test('сначала сортирует неотсканированные, затем по номеру строки', () {
      final ctrl = _controller(repo, db, feedback, _row());
      ctrl.scan!.replaceRows([
        _row(lineNumber: 3),
        _row(lineNumber: 1, qtyActual: 1),
        _row(lineNumber: 2),
      ]);

      expect(ctrl.visibleRows.map((row) => row.lineNumber), [2, 3, 1]);

      ctrl.unscannedFirst = false;
      expect(ctrl.visibleRows.map((row) => row.lineNumber), [1, 2, 3]);
    });
  });

  group('addBarcodeAndReload', () {
    test('POST успешен → done, документ перезагружен', () async {
      when(() => repo.addBarcode(any(), any())).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer((_) async => const Success([]));
      final ctrl = _controller(repo, db, feedback, _row(barcodes: const ['111']));

      final r = await ctrl.addBarcodeAndReload(
        nomenclature: 'Монитор',
        characteristic: 'Black',
        prevBarcodes: const {'111'},
      );

      expect(r.outcome, AddBarcodeOutcome.done);
      expect(r.error, isNull);
      verify(() => repo.addBarcode('Монитор', 'Black')).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1);
    });

    test('POST вернул серверную ошибку → failed + исходная ошибка', () async {
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Failure(ServerError(code: 500)));
      final ctrl = _controller(repo, db, feedback, _row());

      final r = await ctrl.addBarcodeAndReload(
        nomenclature: 'Монитор',
        characteristic: 'Black',
        prevBarcodes: const {},
      );

      expect(r.outcome, AddBarcodeOutcome.failed);
      expect(r.error, isA<ServerError>());
      // Штрихкод не записан — перезагрузку не дёргаем.
      verifyNever(() => repo.getTable(any()));
    });

    test('таймаут POST, но штрихкод появился в перезагрузке → verifiedAfterTimeout', () async {
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      // 1С успела записать — новый штрихкод в обновлённых данных.
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['111', 'NEW']),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row(barcodes: const ['111']));

      final r = await ctrl.addBarcodeAndReload(
        nomenclature: 'Монитор',
        characteristic: 'Black',
        prevBarcodes: const {'111'},
      );

      expect(r.outcome, AddBarcodeOutcome.verifiedAfterTimeout);
      verify(() => repo.getTable('АЕ-1')).called(1);
    });

    test('таймаут POST и перезагрузка тоже упала → inconclusive', () async {
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer((_) async => const Failure(NetworkError()));
      final ctrl = _controller(repo, db, feedback, _row());

      final r = await ctrl.addBarcodeAndReload(
        nomenclature: 'Монитор',
        characteristic: 'Black',
        prevBarcodes: const {},
      );

      expect(r.outcome, AddBarcodeOutcome.inconclusive);
    });

    test('таймаут POST, штрихкод не появился (те же данные) → inconclusive', () async {
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      // Перезагрузка успешна, но штрихкода в данных нет.
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['111']),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row(barcodes: const ['111']));

      final r = await ctrl.addBarcodeAndReload(
        nomenclature: 'Монитор',
        characteristic: 'Black',
        prevBarcodes: const {'111'},
      );

      expect(r.outcome, AddBarcodeOutcome.inconclusive);
    });
  });

  group('addScannedBarcodeAndReload', () {
    test('передаёт считанный ШК и перезагружает документ', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer((_) async => const Success([]));
      final ctrl = _controller(repo, db, feedback, _row());

      final r = await ctrl.addScannedBarcodeAndReload(
        lineNumber: 1,
        nomenclature: 'Монитор',
        characteristic: 'Black',
        barcode: ' 0012345678905 ',
      );

      expect(r.outcome, AddBarcodeOutcome.done);
      verify(() => repo.addScannedBarcode('Монитор', 'Black', '0012345678905')).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1);
    });

    test('после таймаута проверяет конкретный ШК у конкретной строки', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['0012345678905']),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row());

      final r = await ctrl.addScannedBarcodeAndReload(
        lineNumber: 1,
        nomenclature: 'Монитор',
        characteristic: 'Black',
        barcode: '0012345678905',
      );

      expect(r.outcome, AddBarcodeOutcome.verifiedAfterTimeout);
    });

    test('после таймаута локальный ноль не скрывает серверный факт', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['0012345678905'], qtyActual: 3),
        ]),
      );
      when(() => db.getScanProgress('АЕ-1')).thenAnswer(
        (_) async => {
          1: ScanProgressData(
            docCode: 'АЕ-1',
            lineNumber: 1,
            nomenclatureCode: '00-00000123',
            qtyActual: 0,
            action: '',
            updatedAt: DateTime(2026),
          ),
        },
      );
      final ctrl = _controller(repo, db, feedback, _row());

      final r = await ctrl.addScannedBarcodeAndReload(
        lineNumber: 1,
        nomenclature: 'Монитор',
        characteristic: 'Black',
        barcode: '0012345678905',
      );

      expect(r.outcome, AddBarcodeOutcome.verifiedAfterTimeout);
      expect(ctrl.scan!.rows.single.qtyActual, 3);
    });

    test('чужой новый ШК после таймаута не подтверждает операцию', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['ДРУГОЙ']),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row());

      final r = await ctrl.addScannedBarcodeAndReload(
        lineNumber: 1,
        nomenclature: 'Монитор',
        characteristic: 'Black',
        barcode: '0012345678905',
      );

      expect(r.outcome, AddBarcodeOutcome.inconclusive);
    });

    test('ошибка POST не показывается, если регистр подтверждает ту же позицию', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(ServerError(code: 500)));
      when(() => repo.getBarcodeAssignment('460123')).thenAnswer(
        (_) async => const Success(
          BarcodeAssignment(nomenclature: '015.020.063.00052 Седло', characteristic: ''),
        ),
      );
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(nomenclature: 'Седло', nomenclatureCode: '015.020.063.00052', characteristic: ''),
        ]),
      );
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(nomenclature: 'Седло', nomenclatureCode: '015.020.063.00052', characteristic: ''),
      );

      final result = await ctrl.addScannedBarcodeAndReload(
        lineNumber: 1,
        nomenclature: 'Седло',
        characteristic: '',
        barcode: '460123',
      );

      expect(result.outcome, AddBarcodeOutcome.verifiedAfterTimeout);
      expect(ctrl.scan!.rows.single.barcodes, ['460123']);
    });
  });

  group('assignUnknownBarcodeAndReload', () {
    test('успех привязки добавляет позицию в открытый документ', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(() => repo.addNewLine(any(), any(), any())).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(lineNumber: 2, nomenclature: 'Клавиатура', characteristic: '', qtyActual: 1),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row());

      final result = await ctrl.assignUnknownBarcodeAndReload(
        nomenclature: 'Клавиатура',
        characteristic: '',
        barcode: ' 123 ',
      );

      expect(result.outcome, AddBarcodeOutcome.done);
      verify(() => repo.addScannedBarcode('Клавиатура', '', '123')).called(1);
      verify(() => repo.addNewLine('АЕ-1', 'Клавиатура', '')).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1);
      expect(ctrl.scan!.rows.single.qtyActual, 1);
    });

    test('после таймаута проверяет глобальную привязку по штрихкоду', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getBarcodeAssignment('123')).thenAnswer(
        (_) async =>
            const Success(BarcodeAssignment(nomenclature: 'Клавиатура', characteristic: 'Белая')),
      );
      when(() => repo.addNewLine(any(), any(), any())).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async =>
            Success([_row(lineNumber: 2, nomenclature: 'Клавиатура', characteristic: 'Белая')]),
      );
      final ctrl = _controller(repo, db, feedback, _row());

      final result = await ctrl.assignUnknownBarcodeAndReload(
        nomenclature: 'Клавиатура',
        characteristic: 'Белая',
        barcode: '123',
      );

      expect(result.outcome, AddBarcodeOutcome.verifiedAfterTimeout);
      verify(() => repo.getBarcodeAssignment('123')).called(1);
    });

    test('чужая привязка после таймаута не подтверждает успех', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getBarcodeAssignment('123')).thenAnswer(
        (_) async =>
            const Success(BarcodeAssignment(nomenclature: 'Другая позиция', characteristic: '')),
      );
      final ctrl = _controller(repo, db, feedback, _row());

      final result = await ctrl.assignUnknownBarcodeAndReload(
        nomenclature: 'Клавиатура',
        characteristic: '',
        barcode: '123',
      );

      expect(result.outcome, AddBarcodeOutcome.inconclusive);
      verifyNever(() => repo.getTable(any()));
    });

    test('после ошибки повторной записи продолжает добавление уже созданного ШК', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(ServerError(code: 409)));
      when(() => repo.getBarcodeAssignment('123')).thenAnswer(
        (_) async =>
            const Success(BarcodeAssignment(nomenclature: 'Клавиатура', characteristic: 'Белая')),
      );
      when(() => repo.addNewLine(any(), any(), any())).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(lineNumber: 2, nomenclature: 'Клавиатура', characteristic: 'Белая', qtyActual: 1),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row());

      final result = await ctrl.assignUnknownBarcodeAndReload(
        nomenclature: 'Клавиатура',
        characteristic: 'Белая',
        barcode: '123',
      );

      expect(result.outcome, AddBarcodeOutcome.verifiedAfterTimeout);
      verify(() => repo.addNewLine('АЕ-1', 'Клавиатура', 'Белая')).called(1);
      expect(ctrl.scan!.rows.single.qtyActual, 1);
    });

    test('добавляет позицию без характеристики, когда каталог содержит код в названии', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(() => repo.addNewLine(any(), any(), any())).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(
            lineNumber: 2,
            nomenclature: 'Седло',
            nomenclatureCode: '015.020.063.00052',
            characteristic: '',
            qtyActual: 1,
          ),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row());

      final result = await ctrl.assignUnknownBarcodeAndReload(
        nomenclature: '015.020.063.00052 Седло',
        characteristic: '',
        barcode: '460123',
      );

      expect(result.outcome, AddBarcodeOutcome.done);
      expect(ctrl.scan!.rows.single.qtyActual, 1);
      expect(ctrl.scan!.rows.single.barcodes, ['460123']);
    });
  });

  group('deleteBarcodeAndReload', () {
    test('передаёт ШК и обновляет документ', () async {
      when(() => repo.deleteBarcode(any())).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['222']),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row(barcodes: const ['111', '222']));

      final r = await ctrl.deleteBarcodeAndReload(lineNumber: 1, barcode: ' 111 ');

      expect(r.outcome, DeleteBarcodeOutcome.done);
      verify(() => repo.deleteBarcode('111')).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1);
      expect(ctrl.scan!.rows.single.barcodes, const ['222']);
    });

    test('успешное удаление отражается локально при ошибке обновления', () async {
      when(() => repo.deleteBarcode(any())).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer((_) async => const Failure(NetworkError()));
      final ctrl = _controller(repo, db, feedback, _row(barcodes: const ['111', '222']));

      final r = await ctrl.deleteBarcodeAndReload(lineNumber: 1, barcode: '111');

      expect(r.outcome, DeleteBarcodeOutcome.done);
      expect(ctrl.scan!.rows.single.barcodes, const ['222']);
    });

    test('после сетевой ошибки исчезновение ШК подтверждает удаление', () async {
      when(() => repo.deleteBarcode(any())).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['222']),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row(barcodes: const ['111', '222']));

      final r = await ctrl.deleteBarcodeAndReload(lineNumber: 1, barcode: '111');

      expect(r.outcome, DeleteBarcodeOutcome.verifiedAfterTimeout);
      expect(ctrl.scan!.rows.single.barcodes, const ['222']);
    });

    test('после сетевой ошибки оставшийся ШК не подтверждает удаление', () async {
      when(() => repo.deleteBarcode(any())).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['111', '222']),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row(barcodes: const ['111', '222']));

      final r = await ctrl.deleteBarcodeAndReload(lineNumber: 1, barcode: '111');

      expect(r.outcome, DeleteBarcodeOutcome.inconclusive);
    });
  });

  group('deleteLineAndReload', () {
    test('передаёт документ и номер строки, затем удаляет строку локально', () async {
      when(() => repo.deleteLine(any(), any())).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer((_) async => const Success(<DocTableRow>[]));
      final row = _row(lineNumber: 11);
      final ctrl = _controller(repo, db, feedback, row);

      final result = await ctrl.deleteLineAndReload(row: row);

      expect(result.outcome, DeleteLineOutcome.done);
      verify(() => repo.deleteLine('АЕ-1', 11)).called(1);
      verify(() => db.deleteScanProgressLine('АЕ-1', 11)).called(1);
      expect(ctrl.scan!.rows, isEmpty);
    });

    test('после сетевой ошибки исчезновение строки подтверждает удаление', () async {
      when(
        () => repo.deleteLine(any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer((_) async => const Success(<DocTableRow>[]));
      final row = _row(lineNumber: 11);
      final ctrl = _controller(repo, db, feedback, row);

      final result = await ctrl.deleteLineAndReload(row: row);

      expect(result.outcome, DeleteLineOutcome.verifiedAfterTimeout);
      verify(() => db.deleteScanProgressLine('АЕ-1', 11)).called(1);
      expect(ctrl.scan!.rows, isEmpty);
    });

    test('перенумерованная после удаления другая позиция сохраняется', () async {
      when(() => repo.deleteLine(any(), any())).thenAnswer((_) async => const Success(null));
      final deleted = _row(lineNumber: 11, nomenclature: 'Линейка');
      final remaining = _row(lineNumber: 11, nomenclature: 'Корпус', nomenclatureCode: '618810');
      when(() => repo.getTable(any())).thenAnswer((_) async => Success([remaining]));
      final ctrl = _controller(repo, db, feedback, deleted);

      final result = await ctrl.deleteLineAndReload(row: deleted);

      expect(result.outcome, DeleteLineOutcome.done);
      expect(ctrl.scan!.rows.single.nomenclature, 'Корпус');
    });

    test('оставшаяся после сетевой ошибки позиция не считается удалённой', () async {
      when(
        () => repo.deleteLine(any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      final row = _row(lineNumber: 11);
      when(() => repo.getTable(any())).thenAnswer((_) async => Success([row]));
      final ctrl = _controller(repo, db, feedback, row);

      final result = await ctrl.deleteLineAndReload(row: row);

      expect(result.outcome, DeleteLineOutcome.inconclusive);
      verifyNever(() => db.deleteScanProgressLine(any(), any()));
      expect(ctrl.scan!.rows, hasLength(1));
    });
  });
}
