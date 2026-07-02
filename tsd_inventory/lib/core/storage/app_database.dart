import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Прогресс сканирования: одна строка на (docCode, lineNumber).
/// Восстанавливается при перезапуске приложения.
class ScanProgress extends Table {
  TextColumn get docCode => text()();
  IntColumn get lineNumber => integer()();
  TextColumn get nomenclatureCode => text().nullable()();
  IntColumn get qtyActual => integer().withDefault(const Constant(0))();
  TextColumn get action => text().nullable()();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {docCode, lineNumber};
}

/// Кэш табличной части документа (сырой JSON /code/) для офлайн-доступа.
class CachedDoc extends Table {
  TextColumn get code => text()();
  TextColumn get json => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {code};
}

/// Документы, полностью отправленные в 1С (по кнопке «Завершить»).
/// Локальный флаг для метки «✓ Отправлен» в списке документов.
class CompletedDoc extends Table {
  TextColumn get code => text()();
  DateTimeColumn get completedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {code};
}

@DriftDatabase(tables: [ScanProgress, CachedDoc, CompletedDoc])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(completedDoc);
          }
        },
      );

  // --- ScanProgress ---

  /// Вставка/обновление прогресса одной строки.
  Future<void> upsertScanProgress({
    required String docCode,
    required int lineNo,
    String? nomenclatureCode,
    required int qtyActual,
    String? action,
  }) async {
    await into(scanProgress).insertOnConflictUpdate(
      ScanProgressCompanion.insert(
        docCode: docCode,
        lineNumber: lineNo,
        nomenclatureCode: Value(nomenclatureCode),
        qtyActual: Value(qtyActual),
        action: Value(action),
      ),
    );
  }

  /// Восстановление прогресса: lineNumber → строка.
  Future<Map<int, ScanProgressData>> getScanProgress(String docCode) async {
    final rows = await (select(scanProgress)
          ..where((t) => t.docCode.equals(docCode)))
        .get();
    return {for (final r in rows) r.lineNumber: r};
  }

  /// Очистка прогресса документа (после успешной отправки).
  Future<void> clearScanProgress(String docCode) async {
    await (delete(scanProgress)..where((t) => t.docCode.equals(docCode))).go();
  }

  // --- CachedDoc ---

  Future<void> cacheDoc(String code, String json) async {
    await into(cachedDoc).insertOnConflictUpdate(
      CachedDocCompanion.insert(
        code: code,
        json: json,
        fetchedAt: DateTime.now(),
      ),
    );
  }

  Future<CachedDocData?> getCachedDoc(String code) async {
    final q = select(cachedDoc)
      ..where((t) => t.code.equals(code))
      ..limit(1);
    return q.getSingleOrNull();
  }

  Future<void> clearCachedDoc(String code) async {
    await (delete(cachedDoc)..where((t) => t.code.equals(code))).go();
  }

  // --- CompletedDoc ---

  /// Пометить документ как полностью отправленный в 1С.
  Future<void> markDocCompleted(String code) async {
    await into(completedDoc).insertOnConflictUpdate(
      CompletedDocCompanion.insert(code: code),
    );
  }

  /// Все коды документов, помеченных отправленными.
  Future<Set<String>> allCompletedDocCodes() async {
    final rows = await select(completedDoc).get();
    return {for (final r in rows) r.code};
  }

  /// Снять пометку «отправлен» (например, ручная отмена пользователем).
  Future<void> unmarkDocCompleted(String code) async {
    await (delete(completedDoc)..where((t) => t.code.equals(code))).go();
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'tsd_inventory.sqlite'));
    return NativeDatabase(file);
  });
}
