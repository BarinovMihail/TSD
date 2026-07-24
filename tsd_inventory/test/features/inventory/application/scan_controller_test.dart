import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/feedback/feedback_service.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/application/scan_controller.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_assignment.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

class _MockRepo extends Mock implements InventoryRepository {}

class _MockDb extends Mock implements AppDatabase {}

class _MockFeedback extends Mock implements FeedbackService {}

DocTableRow _row(
  int line, {
  String? nomenclature,
  String characteristic = '',
  List<String> barcodes = const [],
  int qtyActual = 0,
}) => DocTableRow(
  lineNumber: line,
  inventoryNumber: '',
  nomenclature: nomenclature ?? 'N$line',
  nomenclatureCode: 'k$line',
  characteristic: characteristic,
  series: '',
  seriesStatus: '0',
  fio: '',
  qtyAccounting: 1,
  qtyActual: qtyActual,
  action: '',
  barcodes: barcodes,
);

ScanController _controller({
  required _MockRepo repo,
  required _MockDb db,
  required _MockFeedback feedback,
  required List<DocTableRow> rows,
}) {
  return ScanController(
    docCode: 'АЕ-1',
    initialRows: rows,
    repo: repo,
    db: db,
    matcher: BarcodeMatcher(),
    feedback: feedback,
  );
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
    when(() => feedback.error()).thenAnswer((_) async {});
    when(() => feedback.attention()).thenAnswer((_) async {});
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
      () => db.getScanProgress(any()),
    ).thenAnswer((_) async => <int, ScanProgressData>{});
    when(() => db.clearScanProgress(any())).thenAnswer((_) async {});
    when(() => db.markDocCompleted(any())).thenAnswer((_) async {});
  });

  test(
    'совпадение с единственным штрихкодом → +1 факт, success, persist',
    () async {
      final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [
          _row(1, barcodes: ['2000000009070']),
          _row(2, barcodes: []),
        ],
      );
      final out = await controller.onScanned('2000000009070');
      expect(out, isA<Found>());
      expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 1);
      verify(() => feedback.success()).called(1);
      verify(
        () => db.upsertScanProgress(
          docCode: 'АЕ-1',
          lineNo: 1,
          nomenclatureCode: any(named: 'nomenclatureCode'),
          qtyActual: 1,
          action: any(named: 'action'),
        ),
      ).called(1);
    },
  );

  test('совпадение со вторым штрихкодом позиции → +1 факт', () async {
    final controller = _controller(
      repo: repo,
      db: db,
      feedback: feedback,
      rows: [
        _row(1, barcodes: ['111', '222', '333']),
      ],
    );
    final out = await controller.onScanned('333');
    expect(out, isA<Found>());
    expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 1);
  });

  test('повторный скан той же строки → ещё +1', () async {
    final controller = _controller(
      repo: repo,
      db: db,
      feedback: feedback,
      rows: [
        _row(1, barcodes: ['111']),
      ],
    );
    await controller.onScanned('111');
    await controller.onScanned('111');
    expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 2);
  });

  test(
    'штрихкод не найден ни у одной строки → NotFoundInDocument, error',
    () async {
      final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [
          _row(1, barcodes: ['111']),
        ],
      );
      final out = await controller.onScanned('999');
      expect(out, isA<NotFoundInDocument>());
      expect((out as NotFoundInDocument).code, '999');
      verify(() => feedback.error()).called(1);
      // Факт не менялся, в БД ничего не писали.
      verifyNever(
        () => db.upsertScanProgress(
          docCode: any(named: 'docCode'),
          lineNo: any(named: 'lineNo'),
          nomenclatureCode: any(named: 'nomenclatureCode'),
          qtyActual: any(named: 'qtyActual'),
          action: any(named: 'action'),
        ),
      );
    },
  );

  test(
    'одинаковый штрихкод у нескольких строк → Ambiguous, attention',
    () async {
      final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [
          _row(1, barcodes: ['SHARED']),
          _row(2, barcodes: ['SHARED']),
        ],
      );
      final out = await controller.onScanned('SHARED');
      expect(out, isA<Ambiguous>());
      expect((out as Ambiguous).candidates.length, 2);
      verify(() => feedback.attention()).called(1);
    },
  );

  test('applyChoice инкрементирует выбранную строку', () async {
    final controller = _controller(
      repo: repo,
      db: db,
      feedback: feedback,
      rows: [
        _row(1, barcodes: ['SHARED']),
        _row(2, barcodes: ['SHARED']),
      ],
    );
    final row = controller.rows.firstWhere((r) => r.lineNumber == 2);
    await controller.applyChoice(row);
    expect(controller.rows.firstWhere((r) => r.lineNumber == 2).qtyActual, 1);
  });

  test('пробелы вокруг отсканированного значения → trim', () async {
    final controller = _controller(
      repo: repo,
      db: db,
      feedback: feedback,
      rows: [
        _row(1, barcodes: ['111']),
      ],
    );
    final out = await controller.onScanned('  111  ');
    expect(out, isA<Found>());
    expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 1);
  });

  test('ведущие нули сохраняются при сопоставлении', () async {
    final controller = _controller(
      repo: repo,
      db: db,
      feedback: feedback,
      rows: [
        _row(1, barcodes: ['007890']),
      ],
    );
    expect((await controller.onScanned('007890')), isA<Found>());
    expect((await controller.onScanned('7890')), isA<NotFoundInDocument>());
  });

  test('пустой после trim → ScanIgnored, ничего не меняется', () async {
    final controller = _controller(
      repo: repo,
      db: db,
      feedback: feedback,
      rows: [
        _row(1, barcodes: ['111']),
      ],
    );
    final out = await controller.onScanned('   ');
    expect(out, isA<ScanIgnored>());
    expect(controller.rows.first.qtyActual, 0);
    verifyNever(() => feedback.error());
    verifyNever(() => feedback.success());
  });

  test('scannedCount / total', () async {
    final controller = _controller(
      repo: repo,
      db: db,
      feedback: feedback,
      rows: [
        _row(1, barcodes: ['111']),
        _row(2, barcodes: ['222']),
      ],
    );
    expect(controller.total, 2);
    expect(controller.scannedCount, 0);
    await controller.onScanned('111');
    expect(controller.scannedCount, 1);
  });

  test('обновлённые штрихкоды используются после replaceRows', () async {
    final controller = _controller(
      repo: repo,
      db: db,
      feedback: feedback,
      rows: [_row(1, barcodes: [])],
    );
    // До обновления штрихкода нет.
    expect((await controller.onScanned('444')), isA<NotFoundInDocument>());
    // После перезагрузки документа штрихкод появился.
    controller.replaceRows([
      _row(1, barcodes: ['444']),
    ]);
    expect((await controller.onScanned('444')), isA<Found>());
  });

  group('позиция из регистра', () {
    const assignment = BarcodeAssignment(
      nomenclature: 'Клавиатура',
      characteristic: 'Белая',
    );

    test('существующая строка получает факт +1', () async {
      final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [
          _row(
            1,
            nomenclature: 'Клавиатура',
            characteristic: 'Белая',
          ),
        ],
      );

      final result = await controller.onRegisteredBarcode('123', assignment);

      expect(result, isA<Found>());
      expect(controller.rows.single.qtyActual, 1);
    });

    test('отсутствующая строка предлагает добавление в документ', () async {
      final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, nomenclature: 'Монитор')],
      );

      final result = await controller.onRegisteredBarcode('123', assignment);

      expect(result, isA<NotFoundInDocument>());
    });

    test(
      'addMissingLine вызывает /newStr, перечитывает документ и ставит факт',
      () async {
        when(
          () => repo.addNewLine(any(), any(), any()),
        ).thenAnswer((_) async => const Success(null));
        when(() => repo.getTable('АЕ-1')).thenAnswer(
          (_) async => Success([
            _row(1, nomenclature: 'Монитор'),
            _row(
              2,
              nomenclature: 'Клавиатура',
              characteristic: 'Белая',
            ),
          ]),
        );
        final controller = _controller(
          repo: repo,
          db: db,
          feedback: feedback,
          rows: [_row(1, nomenclature: 'Монитор')],
        );

        final result = await controller.addMissingLine(assignment);

        expect(result, isA<Success<void>>());
        verify(
          () => repo.addNewLine('АЕ-1', 'Клавиатура', 'Белая'),
        ).called(1);
        expect(
          controller.rows.firstWhere((row) => row.lineNumber == 2).qtyActual,
          1,
        );
      },
    );
  });

  group('hydrateFromDb', () {
    test('локальный ноль не затирает положительный факт из 1С', () async {
      when(() => db.getScanProgress('АЕ-1')).thenAnswer(
        (_) async => {
          1: ScanProgressData(
            docCode: 'АЕ-1',
            lineNumber: 1,
            nomenclatureCode: 'k1',
            qtyActual: 0,
            action: '',
            updatedAt: DateTime(2026),
          ),
        },
      );
      final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, qtyActual: 3)],
      );

      await controller.hydrateFromDb();

      expect(controller.rows.single.qtyActual, 3);
    });

    test('положительный локальный прогресс восстанавливается поверх 1С', () async {
      when(() => db.getScanProgress('АЕ-1')).thenAnswer(
        (_) async => {
          1: ScanProgressData(
            docCode: 'АЕ-1',
            lineNumber: 1,
            nomenclatureCode: 'k1',
            qtyActual: 2,
            action: '',
            updatedAt: DateTime(2026),
          ),
        },
      );
      final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, qtyActual: 0)],
      );

      await controller.hydrateFromDb();

      expect(controller.rows.single.qtyActual, 2);
    });
  });

  group('commit', () {
    test(
      'успех → отправка в репозиторий, очистка прогресса и пометка «отправлен»',
      () async {
        when(
          () => repo.postDocResult(any(), any<Map<int, LineResult>>()),
        ).thenAnswer((_) async => const Success(null));
        final controller = _controller(
          repo: repo,
          db: db,
          feedback: feedback,
          rows: [
            _row(1, barcodes: ['111']),
            _row(2, barcodes: ['222']),
          ],
        );
        await controller.onScanned('111'); // строка 1 → факт 1
        await controller.onScanned('222'); // строка 2 → факт 1

        final res = await controller.commit();

        expect(res, isA<Success>());
        final captured = verify(
          () => repo.postDocResult(
            captureAny(),
            captureAny<Map<int, LineResult>>(),
          ),
        ).captured;
        expect(captured[0], 'АЕ-1');
        final lines = captured[1] as Map<int, LineResult>;
        expect(lines[1]?.qty, 1);
        expect(lines[2]?.qty, 1);
        verify(() => db.clearScanProgress('АЕ-1')).called(1);
        verify(() => db.markDocCompleted('АЕ-1')).called(1);
      },
    );

    test(
      'сбой записи → прогресс НЕ очищается и НЕ помечается отправленным',
      () async {
        when(
          () => repo.postDocResult(any(), any<Map<int, LineResult>>()),
        ).thenAnswer((_) async => const Failure(ServerError(code: 500)));
        final controller = _controller(
          repo: repo,
          db: db,
          feedback: feedback,
          rows: [
            _row(1, barcodes: ['111']),
          ],
        );
        await controller.onScanned('111');

        final res = await controller.commit();

        expect(res, isA<Failure>());
        verifyNever(() => db.clearScanProgress(any()));
        verifyNever(() => db.markDocCompleted(any()));
      },
    );
  });
}
