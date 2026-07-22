import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/core/feedback/feedback_service.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/application/inventory_screen_controller.dart';
import 'package:tsd_inventory/features/inventory/application/scan_controller.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';
import 'package:tsd_inventory/features/inventory/presentation/barcode_dialog.dart';
import 'package:tsd_inventory/l10n/app_strings.dart';

class _MockRepo extends Mock implements InventoryRepository {}

class _MockDb extends Mock implements AppDatabase {}

class _MockFeedback extends Mock implements FeedbackService {}

DocTableRow _row({
  String nomenclature = 'Монитор',
  String characteristic = '',
  List<String> barcodes = const [],
}) => DocTableRow(
  lineNumber: 1,
  inventoryNumber: '',
  nomenclature: nomenclature,
  nomenclatureCode: '00-00000123',
  characteristic: characteristic,
  series: '',
  seriesStatus: '0',
  fio: '',
  qtyAccounting: 1,
  qtyActual: 0,
  action: '',
  barcodes: barcodes,
);

/// Создаёт контроллер с предзагруженной одной строкой (без хождения в сеть
/// при init — строки задаём сразу, scan создаём вручную).
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
    when(() => feedback.error()).thenAnswer((_) async {});
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
  });

  Widget wrap(Widget child, InventoryScreenController ctrl) {
    return ProviderScope(
      overrides: [
        inventoryScreenControllerProvider('АЕ-1').overrideWith((ref) => ctrl),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('AddBarcodeDialog', () {
    testWidgets(
      'характеристика уже заполнена → показывается, без загрузки списка',
      (tester) async {
        when(
          () => repo.getCharacteristics(any()),
        ).thenAnswer((_) async => const Success(['Black']));
        final ctrl = _controller(
          repo,
          db,
          feedback,
          _row(characteristic: 'Black'),
        );

        await tester.pumpWidget(
          wrap(AddBarcodeDialog(row: ctrl.scan!.rows.first, ctrl: ctrl), ctrl),
        );
        await tester.pump();

        expect(find.text('Black'), findsOneWidget);
        // Список характеристик не подгружается — он уже есть.
        verifyNever(() => repo.getCharacteristics(any()));
      },
    );

    testWidgets('пустая характеристика → «Без характеристики» отправляет ""', (
      tester,
    ) async {
      when(
        () => repo.getCharacteristics(any()),
      ).thenAnswer((_) async => const Success(['A', 'B']));
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(
        () => repo.getTable(any()),
      ).thenAnswer((_) async => const Success([]));
      final ctrl = _controller(repo, db, feedback, _row(characteristic: ''));

      await tester.pumpWidget(
        wrap(AddBarcodeDialog(row: ctrl.scan!.rows.first, ctrl: ctrl), ctrl),
      );
      await tester.pumpAndSettle();

      // По умолчанию выбран «Без характеристики».
      await tester.tap(find.text('Добавить штрихкод'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => repo.addBarcode(captureAny(), captureAny()),
      ).captured;
      expect(captured[0], 'Монитор');
      expect(captured[1], '');
    });

    testWidgets(
      'блокировка повторного нажатия: addBarcode вызывается один раз',
      (tester) async {
        when(
          () => repo.getCharacteristics(any()),
        ).thenAnswer((_) async => const Success(['A']));
        // Имитируем медленный addBarcode, чтобы второе нажатие успело произойти.
        var calls = 0;
        when(() => repo.addBarcode(any(), any())).thenAnswer((_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return const Success(null);
        });
        when(
          () => repo.getTable(any()),
        ).thenAnswer((_) async => const Success([]));
        final ctrl = _controller(repo, db, feedback, _row(characteristic: ''));

        await tester.pumpWidget(
          wrap(AddBarcodeDialog(row: ctrl.scan!.rows.first, ctrl: ctrl), ctrl),
        );
        await tester.pumpAndSettle();

        // Быстрое двойное нажатие.
        await tester.tap(find.text('Добавить штрихкод'));
        await tester.tap(find.text('Добавить штрихкод'));
        await tester.pumpAndSettle();

        expect(calls, 1);
      },
    );

    testWidgets('успех POST → перезагрузка документа', (tester) async {
      when(
        () => repo.getCharacteristics(any()),
      ).thenAnswer((_) async => const Success(['A']));
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(
        () => repo.getTable(any()),
      ).thenAnswer((_) async => const Success([]));
      final ctrl = _controller(repo, db, feedback, _row(characteristic: ''));

      await tester.pumpWidget(
        wrap(AddBarcodeDialog(row: ctrl.scan!.rows.first, ctrl: ctrl), ctrl),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Добавить штрихкод'));
      await tester.pumpAndSettle();

      verify(() => repo.addBarcode(any(), any())).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1); // перезагрузка
      expect(find.text('Штрихкод успешно добавлен'), findsOneWidget);
    });

    testWidgets('ошибка POST (сервер) → окно открыто, есть «Повторить»', (
      tester,
    ) async {
      when(
        () => repo.getCharacteristics(any()),
      ).thenAnswer((_) async => const Success(['A']));
      // Серверная ошибка (НЕ таймаут) — штрихкод не записан, перезагрузка
      // не выполняется.
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Failure(ServerError(code: 500)));
      final ctrl = _controller(repo, db, feedback, _row(characteristic: ''));

      await tester.pumpWidget(
        wrap(AddBarcodeDialog(row: ctrl.scan!.rows.first, ctrl: ctrl), ctrl),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Добавить штрихкод'));
      await tester.pumpAndSettle();

      // Окно не закрылось — кнопка добавления ещё на экране.
      expect(find.text('Добавить штрихкод'), findsOneWidget);
      verifyNever(() => repo.getTable(any()));
    });

    testWidgets('таймаут POST, но штрихкод записан → успех, окно закрывается', (
      tester,
    ) async {
      when(
        () => repo.getCharacteristics(any()),
      ).thenAnswer((_) async => const Success(['A']));
      // POST не получил ответа (таймаут), но 1С успела записать штрихкод.
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['NEW']),
        ]),
      );
      final ctrl = _controller(repo, db, feedback, _row(characteristic: ''));

      await tester.pumpWidget(
        wrap(AddBarcodeDialog(row: ctrl.scan!.rows.first, ctrl: ctrl), ctrl),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Добавить штрихкод'));
      await tester.pumpAndSettle();

      // Проверили перезагрузкой — штрихкод появился → окно закрылось.
      verify(() => repo.getTable('АЕ-1')).called(1);
      expect(find.text('Добавление штрихкода'), findsNothing);
    });

    testWidgets(
      'таймаут POST и штрихкод не подтвердился → «Повторить», окно открыто',
      (tester) async {
        when(
          () => repo.getCharacteristics(any()),
        ).thenAnswer((_) async => const Success(['A']));
        when(
          () => repo.addBarcode(any(), any()),
        ).thenAnswer((_) async => const Failure(NetworkError()));
        // Перезагрузка вернула те же данные — нового штрихкода нет.
        when(
          () => repo.getTable(any()),
        ).thenAnswer((_) async => const Success([]));
        final ctrl = _controller(repo, db, feedback, _row(characteristic: ''));

        await tester.pumpWidget(
          wrap(AddBarcodeDialog(row: ctrl.scan!.rows.first, ctrl: ctrl), ctrl),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Добавить штрихкод'));
        await tester.pumpAndSettle();

        // Окно открыто, есть повтор.
        expect(find.text('Добавить штрихкод'), findsOneWidget);
      },
    );

    testWidgets('ошибка загрузки характеристик → кнопка «Повторить»', (
      tester,
    ) async {
      when(
        () => repo.getCharacteristics(any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      final ctrl = _controller(repo, db, feedback, _row(characteristic: ''));

      await tester.pumpWidget(
        wrap(AddBarcodeDialog(row: ctrl.scan!.rows.first, ctrl: ctrl), ctrl),
      );
      await tester.pumpAndSettle();

      expect(find.text('Повторить'), findsOneWidget);
    });
  });

  group('ViewBarcodesDialog', () {
    testWidgets('показывает все штрихкоды позиции', (tester) async {
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(barcodes: const ['111', '222', '333']),
      );

      await tester.pumpWidget(
        wrap(ViewBarcodesDialog(lineNumber: 1, ctrl: ctrl), ctrl),
      );
      await tester.pump();

      expect(find.text('111'), findsOneWidget);
      expect(find.text('222'), findsOneWidget);
      expect(find.text('333'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
    });

    testWidgets('удаление требует подтверждения и обновляет список', (
      tester,
    ) async {
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

      await tester.pumpWidget(
        wrap(ViewBarcodesDialog(lineNumber: 1, ctrl: ctrl), ctrl),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Удалить штрихкод 111'));
      await tester.pumpAndSettle();
      expect(find.text('Удалить штрихкод 111?'), findsOneWidget);
      verifyNever(() => repo.deleteBarcode(any()));

      final deleteButton = find.widgetWithText(FilledButton, 'Удалить');
      final cancelButton = find.widgetWithText(OutlinedButton, 'Отмена');
      expect(
        tester.getSize(deleteButton).width,
        tester.getSize(cancelButton).width,
      );

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      verify(() => repo.deleteBarcode('111')).called(1);
      expect(find.text('111'), findsNothing);
      expect(find.text('222'), findsOneWidget);
      expect(find.text('Штрихкод успешно удалён'), findsOneWidget);
    });

    testWidgets('отмена не удаляет штрихкод', (tester) async {
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(barcodes: const ['111']),
      );

      await tester.pumpWidget(
        wrap(ViewBarcodesDialog(lineNumber: 1, ctrl: ctrl), ctrl),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Удалить штрихкод 111'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Отмена'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.deleteBarcode(any()));
      expect(find.text('111'), findsOneWidget);
    });

    testWidgets('добавление нового штрихкода → POST + перезагрузка', (
      tester,
    ) async {
      when(
        () => repo.addBarcode(any(), any()),
      ).thenAnswer((_) async => const Success(null));
      // После перезагрузки у позиции появился ещё один штрихкод.
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['111', '444']),
        ]),
      );
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(barcodes: const ['111']),
      );

      await tester.pumpWidget(
        wrap(ViewBarcodesDialog(lineNumber: 1, ctrl: ctrl), ctrl),
      );
      await tester.pump();

      await tester.tap(find.text('Добавить новый штрихкод'));
      await tester.pumpAndSettle();

      verify(() => repo.addBarcode(any(), any())).called(1);
      verify(() => repo.getTable('АЕ-1')).called(1);
      // После перезагрузки в списке появился новый штрихкод.
      expect(find.text('444'), findsOneWidget);
      expect(find.text('Штрихкод успешно добавлен'), findsOneWidget);
    });

    testWidgets('сканирование с товара → POST содержит считанный ШК', (
      tester,
    ) async {
      when(
        () => repo.addScannedBarcode(any(), any(), any()),
      ).thenAnswer((_) async => const Success(null));
      when(() => repo.getTable(any())).thenAnswer(
        (_) async => Success([
          _row(barcodes: const ['111', '0012345678905']),
        ]),
      );
      final ctrl = _controller(
        repo,
        db,
        feedback,
        _row(characteristic: 'Black', barcodes: const ['111']),
      );

      await tester.pumpWidget(
        wrap(
          ViewBarcodesDialog(
            lineNumber: 1,
            ctrl: ctrl,
            onCaptureBarcode: (_) async => '0012345678905',
          ),
          ctrl,
        ),
      );
      await tester.pump();

      await tester.tap(find.text(AppStrings.scanBarcodeFromItem));
      await tester.pumpAndSettle();

      verify(
        () => repo.addScannedBarcode(
          'Монитор',
          'Black',
          '0012345678905',
        ),
      ).called(1);
      expect(find.text('0012345678905'), findsOneWidget);
    });
  });
}
