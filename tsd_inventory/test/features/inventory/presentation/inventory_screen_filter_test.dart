import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/feedback/feedback_service.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/auth/application/auth_controller.dart';
import 'package:tsd_inventory/features/inventory/application/inventory_screen_controller.dart';
import 'package:tsd_inventory/features/inventory/application/scan_controller.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';
import 'package:tsd_inventory/features/inventory/presentation/inventory_screen.dart';
import 'package:tsd_inventory/l10n/app_strings.dart';

class _MockRepo extends Mock implements InventoryRepository {}

class _MockDb extends Mock implements AppDatabase {}

class _MockFeedback extends Mock implements FeedbackService {}

DocTableRow _row(int line, {List<String> barcodes = const []}) => DocTableRow(
  lineNumber: line,
  inventoryNumber: '',
  nomenclature: 'Номенклатура $line',
  nomenclatureCode: 'k$line',
  characteristic: '',
  series: '',
  seriesStatus: '0',
  fio: '',
  qtyAccounting: 1,
  qtyActual: 0,
  action: '',
  barcodes: barcodes,
);

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

  /// Создаёт ProviderScope с готовым контроллером (две строки: одна со
  /// штрихкодом, одна без), чтобы экран не ходил в сеть.
  Widget harness() {
    return ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        inventoryScreenControllerProvider('АЕ-1').overrideWith((ref) {
          final c = InventoryScreenController(
            docCode: 'АЕ-1',
            repo: repo,
            db: db,
            matcher: BarcodeMatcher(),
            feedback: feedback,
          );
          c.scan = ScanController(
            docCode: 'АЕ-1',
            initialRows: [
              _row(1, barcodes: const ['111']), // со штрихкодом
              _row(2, barcodes: const []), // без штрихкода
            ],
            repo: repo,
            db: db,
            matcher: BarcodeMatcher(),
            feedback: feedback,
          );
          c.loading = false;
          return c;
        }),
      ],
      child: const MaterialApp(home: InventoryScreen(docCode: 'АЕ-1')),
    );
  }

  testWidgets('фильтр выключен → видны все строки', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.byType(FilterChip), findsNWidgets(2));
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Номенклатура 1'), findsOneWidget);
    expect(find.text('Номенклатура 2'), findsOneWidget);
  });

  testWidgets('фильтр «Только без штрихкода» → только строка без штрихкода', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // Изначально видны обе.
    expect(find.text('Номенклатура 1'), findsOneWidget);
    expect(find.text('Номенклатура 2'), findsOneWidget);

    // Включаем фильтр.
    await tester.tap(find.text(AppStrings.onlyWithoutBarcode));
    await tester.pump();

    // Осталась только строка без штрихкода.
    expect(find.text('Номенклатура 2'), findsOneWidget);
    expect(find.text('Номенклатура 1'), findsNothing);
  });

  testWidgets(
    'фильтр не меняет данные — после выключения обе строки снова видны',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      // Включить, выключить.
      await tester.tap(find.text(AppStrings.onlyWithoutBarcode));
      await tester.pump();
      await tester.tap(find.text(AppStrings.onlyWithoutBarcode));
      await tester.pump();

      expect(find.text('Номенклатура 1'), findsOneWidget);
      expect(find.text('Номенклатура 2'), findsOneWidget);
    },
  );
}

class _FakeAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(
    session: AuthSession(login: 'tester', password: 'pw'),
  );
}
