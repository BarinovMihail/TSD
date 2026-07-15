import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/auth/application/auth_controller.dart';

import '../data/inventory_repository.dart';

/// Singleton drift-базы.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Фабрика InventoryRepository под текущую сессию.
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final session = ref.watch(authControllerProvider).session!;
  final config = ref.watch(appConfigProvider);
  final client = DioClient(
    config: config,
    credentials: BasicCredentials(session.login, session.password),
  );
  final db = ref.watch(appDatabaseProvider);
  return InventoryRepository(client: client, db: db);
});
