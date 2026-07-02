import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/feedback/feedback_service.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/application/scan_controller.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

class _MockRepo extends Mock implements InventoryRepository {}

class _MockDb extends Mock implements AppDatabase {}

class _MockFeedback extends Mock implements FeedbackService {}

DocTableRow _row(int line, String code) => DocTableRow(
      lineNumber: line,
      inventoryNumber: '',
      nomenclature: 'N$line',
      nomenclatureCode: code,
      characteristic: '',
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
    when(() => db.clearScanProgress(any())).thenAnswer((_) async {});
    when(() => db.markDocCompleted(any())).thenAnswer((_) async {});
  });

  test('найдено ровно одно → +1 факт, success, persist', () async {
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, '000123'), _row(2, '000456')]);
    final out = await controller.onScanned('000123');
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
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, '000123')]);
    await controller.onScanned('000123');
    await controller.onScanned('000123');
    expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 2);
  });

  test('не найдено → NotFound, error feedback', () async {
    final controller = _controller(
        repo: repo, db: db, feedback: feedback, rows: [_row(1, '000123')]);
    final out = await controller.onScanned('ZZZ');
    expect(out, isA<NotFound>());
    verify(() => feedback.error()).called(1);
  });

  test('несколько совпадений → Ambiguous, attention', () async {
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, '000123'), _row(2, '000123')]);
    final out = await controller.onScanned('000123');
    expect(out, isA<Ambiguous>());
    expect((out as Ambiguous).candidates.length, 2);
    verify(() => feedback.attention()).called(1);
  });

  test('scannedCount / total', () async {
    final controller = _controller(
        repo: repo,
        db: db,
        feedback: feedback,
        rows: [_row(1, '000123'), _row(2, '000456')]);
    expect(controller.total, 2);
    expect(controller.scannedCount, 0);
    await controller.onScanned('000123');
    expect(controller.scannedCount, 1);
  });

  group('commit', () {
    setUp(() {
      // Нужен для verifyNoMoreInteractions, чтобы разрешить stub-ы прогресса.
    });

    test('успех → отправка в репозиторий, очистка прогресса и пометка «отправлен»',
        () async {
      when(() => repo.postDocResult(any(), any<Map<int, LineResult>>()))
          .thenAnswer((_) async => const Success(null));
      final controller = _controller(
          repo: repo,
          db: db,
          feedback: feedback,
          rows: [_row(1, '000123'), _row(2, '000456')]);
      await controller.onScanned('000123'); // строка 1 → факт 1
      await controller.onScanned('000456'); // строка 2 → факт 1

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
      when(() => repo.postDocResult(any(), any<Map<int, LineResult>>()))
          .thenAnswer((_) async => const Failure(ServerError(code: 500)));
      final controller = _controller(
          repo: repo, db: db, feedback: feedback, rows: [_row(1, '000123')]);
      await controller.onScanned('000123');

      final res = await controller.commit();

      expect(res, isA<Failure>());
      verifyNever(() => db.clearScanProgress(any()));
      verifyNever(() => db.markDocCompleted(any()));
    });
  });
}
