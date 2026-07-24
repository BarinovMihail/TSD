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
  List<String> barcodes = const [],
  int qtyActual = 0,
}) => DocTableRow(
  lineNumber: 1,
  inventoryNumber: '',
  nomenclature: 'Монитор',
  nomenclatureCode: '00-00000123',
  characteristic: 'Black',
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
    when(
      () => db.getScanProgress(any()),
    ).thenAnswer((_) async => <int, ScanProgressData>{});
  });

  test('reload сохраняет серверный факт при локальной записи с нулём', () async {
    when(() => repo.getTable('АЕ-1')).thenAnswer(
      (_) async => Success([_row(qtyActual: 3)]),
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

    final result = await ctrl.reload();

    expect(result, isA<Success>());
    expect(ctrl.scan!.rows.single.qtyActual, 3);
  });

  group('addBarcodeAndReload', () {
    test('POST успешен → done, документ перезагружен', () async {
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(
        () => repo.getTable(any()),
      ).thenAnswer((_) async => const Success([]));
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(barcodes: const ['111']),
      );

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

    test(
      'таймаут POST, но штрихкод появился в перезагрузке → verifiedAfterTimeout',
      () async {
        when(
          () => repo.addBarcode(any(), any()),
        ).thenAnswer((_) async => const Failure(NetworkError()));
        // 1С успела записать — новый штрихкод в обновлённых данных.
        when(() => repo.getTable(any())).thenAnswer(
          (_) async => Success([
            _row(barcodes: const ['111', 'NEW']),
          ]),
        );
        final ctrl = _controller(
          repo,
          db,
          feedback,
          _row(barcodes: const ['111']),
        );

        final r = await ctrl.addBarcodeAndReload(
          nomenclature: 'Монитор',
          characteristic: 'Black',
          prevBarcodes: const {'111'},
        );

        expect(r.outcome, AddBarcodeOutcome.verifiedAfterTimeout);
        verify(() => repo.getTable('АЕ-1')).called(1);
      },
    );

    test('таймаут POST и перезагрузка тоже упала → inconclusive', () async {
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(
        () => repo.getTable(any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      final ctrl = _controller(repo, db, feedback, _row());

      final r = await ctrl.addBarcodeAndReload(
        nomenclature: 'Монитор',
        characteristic: 'Black',
        prevBarcodes: const {},
      );

      expect(r.outcome, AddBarcodeOutcome.inconclusive);
    });

    test(
      'таймаут POST, штрихкод не появился (те же данные) → inconclusive',
      () async {
        when(
          () => repo.addBarcode(any(), any()),
        ).thenAnswer((_) async => const Failure(NetworkError()));
        // Перезагрузка успешна, но штрихкода в данных нет.
        when(() => repo.getTable(any())).thenAnswer(
          (_) async => Success([
            _row(barcodes: const ['111']),
          ]),
        );
        final ctrl = _controller(
          repo,
          db,
          feedback,
          _row(barcodes: const ['111']),
        );

        final r = await ctrl.addBarcodeAndReload(
          nomenclature: 'Монитор',
          characteristic: 'Black',
          prevBarcodes: const {'111'},
        );

        expect(r.outcome, AddBarcodeOutcome.inconclusive);
      },
    );
  });

  group('addScannedBarcodeAndReload', () {
    test('передаёт считанный ШК и перезагружает документ', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(
        () => repo.getTable(any()),
      ).thenAnswer((_) async => const Success([]));
      final ctrl = _controller(repo, db, feedback, _row());

      final r = await ctrl.addScannedBarcodeAndReload(
        lineNumber: 1,
        nomenclature: 'Монитор',
        characteristic: 'Black',
        barcode: ' 0012345678905 ',
      );

      expect(r.outcome, AddBarcodeOutcome.done);
      verify(
        () => repo.addScannedBarcode(
          'Монитор',
          'Black',
          '0012345678905',
        ),
      ).called(1);
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
  });

  group('assignUnknownBarcodeAndReload', () {
    test('успех привязки перечитывает открытый документ', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(
        () => repo.getTable(any()),
      ).thenAnswer((_) async => const Success([]));
      final ctrl = _controller(repo, db, feedback, _row());

      final result = await ctrl.assignUnknownBarcodeAndReload(
        nomenclature: 'Клавиатура',
        characteristic: '',
        barcode: ' 123 ',
      );

      expect(result.outcome, AddBarcodeOutcome.done);
      verify(
        () => repo.addScannedBarcode('Клавиатура', '', '123'),
      ).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1);
    });

    test('после таймаута проверяет глобальную привязку по штрихкоду', () async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getBarcodeAssignment('123')).thenAnswer(
        (_) async => const Success(
          BarcodeAssignment(
            nomenclature: 'Клавиатура',
            characteristic: 'Белая',
          ),
        ),
      );
      when(
        () => repo.getTable(any()),
      ).thenAnswer((_) async => const Success([]));
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
        (_) async => const Success(
          BarcodeAssignment(
            nomenclature: 'Другая позиция',
            characteristic: '',
          ),
        ),
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
  });

  group('deleteBarcodeAndReload', () {
    test('передаёт ШК и обновляет документ', () async {
      when(
        () => repo.deleteBarcode(any()),
      ).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([_row(barcodes: const ['222'])]),
      );
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(barcodes: const ['111', '222']),
      );

      final r = await ctrl.deleteBarcodeAndReload(
        lineNumber: 1,
        barcode: ' 111 ',
      );

      expect(r.outcome, DeleteBarcodeOutcome.done);
      verify(() => repo.deleteBarcode('111')).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1);
      expect(ctrl.scan!.rows.single.barcodes, const ['222']);
    });

    test('успешное удаление отражается локально при ошибке обновления', () async {
      when(
        () => repo.deleteBarcode(any()),
      ).thenAnswer((_) async => const Success(null));
      when(
        () => repo.getTable(any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(barcodes: const ['111', '222']),
      );

      final r = await ctrl.deleteBarcodeAndReload(
        lineNumber: 1,
        barcode: '111',
      );

      expect(r.outcome, DeleteBarcodeOutcome.done);
      expect(ctrl.scan!.rows.single.barcodes, const ['222']);
    });

    test('после сетевой ошибки исчезновение ШК подтверждает удаление', () async {
      when(
        () => repo.deleteBarcode(any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([_row(barcodes: const ['222'])]),
      );
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(barcodes: const ['111', '222']),
      );

      final r = await ctrl.deleteBarcodeAndReload(
        lineNumber: 1,
        barcode: '111',
      );

      expect(r.outcome, DeleteBarcodeOutcome.verifiedAfterTimeout);
      expect(ctrl.scan!.rows.single.barcodes, const ['222']);
    });

    test('после сетевой ошибки оставшийся ШК не подтверждает удаление', () async {
      when(
        () => repo.deleteBarcode(any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([_row(barcodes: const ['111', '222'])]),
      );
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(barcodes: const ['111', '222']),
      );

      final r = await ctrl.deleteBarcodeAndReload(
        lineNumber: 1,
        barcode: '111',
      );

      expect(r.outcome, DeleteBarcodeOutcome.inconclusive);
    });
  });
}
