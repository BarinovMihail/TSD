import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/feedback/feedback_service.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/application/scan_controller.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_info.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

class _MockRepo extends Mock implements InventoryRepository {}

class _MockDb extends Mock implements AppDatabase {}

class _MockFeedback extends Mock implements FeedbackService {}

const _barcode = '2000000009070';

DocTableRow _row(int line,
        {String nom = '', String char = '', String code = ''}) =>
    DocTableRow(
      lineNumber: line,
      inventoryNumber: '',
      nomenclature: nom,
      nomenclatureCode: code,
      characteristic: char,
      series: '',
      seriesStatus: '0',
      fio: '',
      qtyAccounting: 1,
      qtyActual: 0,
      action: '',
    );

ScanController _controller(
    {required _MockRepo repo,
    required _MockDb db,
    required _MockFeedback feedback,
    required List<DocTableRow> rows}) {
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
    when(() => db.upsertScanProgress(
          docCode: any(named: 'docCode'),
          lineNo: any(named: 'lineNo'),
          nomenclatureCode: any(named: 'nomenclatureCode'),
          qtyActual: any(named: 'qtyActual'),
          action: any(named: 'action'),
        )).thenAnswer((_) async {});
    // hydrateFromDb() (вызывается из addMissingLine) читает прогресс из БД.
    when(() => db.getScanProgress(any()))
        .thenAnswer((_) async => <int, ScanProgressData>{});
    when(() => db.clearScanProgress(any())).thenAnswer((_) async {});
    when(() => db.markDocCompleted(any())).thenAnswer((_) async {});
  });

  /// Stub getBarcodeInfo: по умолчанию возвращает данные по штрихкоду.
  void stubBarcodeInfo(BarcodeInfo? info) {
    when(() => repo.getBarcodeInfo(any()))
        .thenAnswer((_) async => Success<BarcodeInfo?>(info));
  }

  test('найдено ровно одно → +1 факт, success, persist', () async {
    stubBarcodeInfo(const BarcodeInfo(
        nomenclature: 'Монитор', characteristic: '23,5" Samsung'));
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [
          _row(1, nom: 'Монитор', char: '23,5" Samsung'),
          _row(2, nom: 'Клавиатура', char: ''),
        ]);
    final out = await controller.onScanned(_barcode);
    expect(out, isA<Found>());
    expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 1);
    verify(() => feedback.success()).called(1);
    verify(() => db.upsertScanProgress(
          docCode: 'АЕ-1',
          lineNo: 1,
          nomenclatureCode: any(named: 'nomenclatureCode'),
          qtyActual: 1,
          action: any(named: 'action'),
        )).called(1);
  });

  test('повторный скан той же строки → ещё +1', () async {
    stubBarcodeInfo(const BarcodeInfo(
        nomenclature: 'Монитор', characteristic: '23,5" Samsung'));
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, nom: 'Монитор', char: '23,5" Samsung')]);
    await controller.onScanned(_barcode);
    await controller.onScanned(_barcode);
    expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 2);
  });

  test('штрихкод не зарегистрирован в 1С (пустой ответ) → BarcodeNotRegistered',
      () async {
    stubBarcodeInfo(null);
    final controller = _controller(
        repo: repo, db: db, feedback: feedback, rows: [_row(1, nom: 'x')]);
    final out = await controller.onScanned(_barcode);
    expect(out, isA<BarcodeNotRegistered>());
    verify(() => feedback.error()).called(1);
    // Факт не менялся, в БД ничего не писали.
    verifyNever(() => db.upsertScanProgress(
          docCode: any(named: 'docCode'),
          lineNo: any(named: 'lineNo'),
          nomenclatureCode: any(named: 'nomenclatureCode'),
          qtyActual: any(named: 'qtyActual'),
          action: any(named: 'action'),
        ));
  });

  test('номенклатура из 1С не сопоставлена строке → NotFoundInDocument',
      () async {
    stubBarcodeInfo(
        const BarcodeInfo(nomenclature: 'Принтер', characteristic: ''));
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, nom: 'Монитор', char: '')]);
    final out = await controller.onScanned(_barcode);
    expect(out, isA<NotFoundInDocument>());
    expect((out as NotFoundInDocument).info.nomenclature, 'Принтер');
    verify(() => feedback.error()).called(1);
  });

  test('несколько совпадений по паре → Ambiguous, attention', () async {
    stubBarcodeInfo(
        const BarcodeInfo(nomenclature: 'Монитор', characteristic: 'Black'));
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [
          _row(1, nom: 'Монитор', char: 'Black'),
          _row(2, nom: 'Монитор', char: 'Black'),
        ]);
    final out = await controller.onScanned(_barcode);
    expect(out, isA<Ambiguous>());
    expect((out as Ambiguous).candidates.length, 2);
    verify(() => feedback.attention()).called(1);
  });

  test('сетевая ошибка запроса штрихкода → LookupError', () async {
    when(() => repo.getBarcodeInfo(any()))
        .thenAnswer((_) async => const Failure<BarcodeInfo?>(NetworkError()));
    final controller = _controller(
        repo: repo, db: db, feedback: feedback, rows: [_row(1, nom: 'x')]);
    final out = await controller.onScanned(_barcode);
    expect(out, isA<LookupError>());
    expect((out as LookupError).error, isA<NetworkError>());
    verify(() => feedback.error()).called(1);
  });

  test('scannedCount / total', () async {
    stubBarcodeInfo(
        const BarcodeInfo(nomenclature: 'Монитор', characteristic: 'Black'));
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [
          _row(1, nom: 'Монитор', char: 'Black'),
          _row(2, nom: 'Клавиатура', char: 'White'),
        ]);
    expect(controller.total, 2);
    expect(controller.scannedCount, 0);
    await controller.onScanned(_barcode);
    expect(controller.scannedCount, 1);
  });

  group('commit', () {
    setUp(() {
      // Нужен для verifyNoMoreInteractions, чтобы разрешить stub-ы прогресса.
    });

    test('успех → отправка в репозиторий, очистка прогресса и пометка «отправлен»',
        () async {
      stubBarcodeInfo(const BarcodeInfo(nomenclature: 'Монитор', characteristic: 'A'));
      when(() => repo.postDocResult(any(), any<Map<int, LineResult>>()))
          .thenAnswer((_) async => const Success(null));
      final controller = _controller(
          repo: repo,
          db: db,
          feedback: feedback,
          rows: [
            _row(1, nom: 'Монитор', char: 'A'),
            _row(2, nom: 'Клавиатура', char: 'B'),
          ]);
      // Эмулируем скан обеих строк: используем разные штрихкоды, чтобы
      // getBarcodeInfo возвращал данные для каждой.
      when(() => repo.getBarcodeInfo(any())).thenAnswer((inv) async =>
          Success<BarcodeInfo?>(BarcodeInfo(
              nomenclature:
                  inv.positionalArguments.single == 'b1' ? 'Монитор' : 'Клавиатура',
              characteristic:
                  inv.positionalArguments.single == 'b1' ? 'A' : 'B')));
      await controller.onScanned('b1'); // строка 1 → факт 1
      await controller.onScanned('b2'); // строка 2 → факт 1

      final res = await controller.commit();

      expect(res, isA<Success>());
      final captured = verify(() => repo.postDocResult(
              captureAny(), captureAny<Map<int, LineResult>>()))
          .captured;
      expect(captured[0], 'АЕ-1');
      final lines = captured[1] as Map<int, LineResult>;
      expect(lines[1]?.qty, 1);
      expect(lines[2]?.qty, 1);
      verify(() => db.clearScanProgress('АЕ-1')).called(1);
      verify(() => db.markDocCompleted('АЕ-1')).called(1);
    });

    test('сбой записи → прогресс НЕ очищается и НЕ помечается отправленным',
        () async {
      stubBarcodeInfo(const BarcodeInfo(nomenclature: 'Монитор', characteristic: 'A'));
      when(() => repo.postDocResult(any(), any<Map<int, LineResult>>()))
          .thenAnswer((_) async => const Failure(ServerError(code: 500)));
      final controller = _controller(
          repo: repo,
          db: db,
          feedback: feedback,
          rows: [_row(1, nom: 'Монитор', char: 'A')]);
      await controller.onScanned(_barcode);

      final res = await controller.commit();

      expect(res, isA<Failure>());
      verifyNever(() => db.clearScanProgress(any()));
      verifyNever(() => db.markDocCompleted(any()));
    });
  });

  group('addMissingLine', () {
    test('успех → newStr + перезагрузка, факт = 1 по добавленной строке',
        () async {
      when(() => repo.addNewLine(any(), any(), any()))
          .thenAnswer((_) async => const Success(null));
      // После добавления 1С возвращает обновлённую табличную часть,
      // где появилась новая строка с парой (Монитор, Black) (lineNumber 3).
      when(() => repo.getTable(any())).thenAnswer((_) async => Success([
            _row(1, nom: 'Клавиатура'),
            _row(2, nom: 'Монитор', char: 'White'),
            _row(3, nom: 'Монитор', char: 'Black'),
          ]));
      final controller = _controller(
          repo: repo,
          db: db,
          feedback: feedback,
          rows: [
            _row(1, nom: 'Клавиатура'),
            _row(2, nom: 'Монитор', char: 'White'),
          ]);

      final res = await controller.addMissingLine(
          const BarcodeInfo(nomenclature: 'Монитор', characteristic: 'Black'));

      expect(res, isA<Success>());
      verify(() => repo.addNewLine('АЕ-1', 'Монитор', 'Black')).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1);
      // Факт = 1 по добавленной строке.
      final added = controller.rows.firstWhere((r) => r.lineNumber == 3);
      expect(added.qtyActual, 1);
      // Прогресс сохранён в БД.
      verify(() => db.upsertScanProgress(
            docCode: 'АЕ-1',
            lineNo: 3,
            nomenclatureCode: any(named: 'nomenclatureCode'),
            qtyActual: 1,
            action: any(named: 'action'),
          )).called(1);
    });

    test('сбой addNewLine → Failure, перезагрузка НЕ вызывается', () async {
      when(() => repo.addNewLine(any(), any(), any()))
          .thenAnswer((_) async => const Failure(ServerError(code: 500)));
      final controller = _controller(
          repo: repo, db: db, feedback: feedback, rows: [_row(1, nom: 'x')]);

      final res = await controller.addMissingLine(
          const BarcodeInfo(nomenclature: 'Монитор', characteristic: 'Black'));

      expect(res, isA<Failure>());
      verifyNever(() => repo.getTable(any()));
    });

    test('строка не вернулась из 1С после добавления → Failure, факт не ставится',
        () async {
      when(() => repo.addNewLine(any(), any(), any()))
          .thenAnswer((_) async => const Success(null));
      // 1С не вернула строку с добавленной парой (Монитор, Black).
      when(() => repo.getTable(any())).thenAnswer(
          (_) async => Success([_row(1, nom: 'Клавиатура'), _row(2, nom: 'Монитор', char: 'White')]));
      final controller = _controller(
          repo: repo, db: db, feedback: feedback, rows: [_row(1, nom: 'Клавиатура')]);

      final res = await controller.addMissingLine(
          const BarcodeInfo(nomenclature: 'Монитор', characteristic: 'Black'));

      expect(res, isA<Failure>());
      // Не должно быть записи в БД по строке, которой нет.
      verifyNever(() => db.upsertScanProgress(
          docCode: any(named: 'docCode'),
          lineNo: any(named: 'lineNo'),
          nomenclatureCode: any(named: 'nomenclatureCode'),
          qtyActual: any(named: 'qtyActual'),
          action: any(named: 'action')));
    });

    // Регрессия: нормализация текста при поиске добавленной строки.
    // 1С может вернуть номенклатуру с лишними пробелами или в другом регистре —
    // матчер (normalize) всё равно сопоставит пару с отправленной.
    test('нормализация: лишние пробелы и регистр не мешают найти строку',
        () async {
      when(() => repo.addNewLine(any(), any(), any()))
          .thenAnswer((_) async => const Success(null));
      // 1С вернула добавленную строку с лишними пробелами и в верхнем регистре.
      when(() => repo.getTable(any())).thenAnswer((_) async => Success([
            _row(1, nom: '  МОНИТОР  24 ', char: 'BLACK'),
          ]));
      final controller = _controller(
          repo: repo, db: db, feedback: feedback, rows: []);

      final res = await controller.addMissingLine(
          const BarcodeInfo(nomenclature: 'Монитор 24', characteristic: 'black'));

      expect(res, isA<Success>());
      final added = controller.rows.firstWhere((r) => r.lineNumber == 1);
      expect(added.qtyActual, 1);
    });
  });
}
