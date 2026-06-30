import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';

import '../domain/doc_table_parser.dart';
import '../domain/doc_table_row.dart';

final _log = Logger('inventory_repository');

/// Запись по строке документа: номер строки → (факт, действие).
typedef LineResult = ({int qty, String action});

/// Табличная часть документа + запись результатов + stub получения ФИО.
/// Стратегия кэш+сеть: при сетевой ошибке fallback на кэш из AppDatabase.
class InventoryRepository {
  InventoryRepository({required DioClient client, required AppDatabase db})
      : _client = client,
        _db = db;

  final DioClient _client;
  final AppDatabase _db;

  /// GET /hs/inventory/code/{Код} → табличная часть.
  /// Сетевая ошибка + есть кэш → отдаём кэш (офлайн).
  Future<Result<List<DocTableRow>>> getTable(String code) async {
    final path = 'hs/inventory/code/${Uri.encodeComponent(code)}';
    try {
      final res = await _client.getJson<dynamic>(path);
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      // Кэшируем сырой ответ.
      await _db.cacheDoc(code, jsonEncode(data));
      return Success(parseDocTable(data));
    } on DioException catch (e) {
      // Попытка отдать кэш.
      final cached = await _db.getCachedDoc(code);
      if (cached != null) {
        _log.warning('Сеть недоступна, отдаю кэш документа $code');
        return Success(parseDocTable(jsonDecode(cached.json)));
      }
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка загрузки табличной части: $e');
      return const Failure(ParseError('Не удалось разобрать табличную часть'));
    }
  }

  /// Запись фактических количеств. Эндпоинт/метод/тело — ПОДЛЕЖАТ уточнению 1С.
  /// TODO(1С): уточнить URL/метод/тело с разработчиком 1С.
  /// Предполагаемый: POST /hs/inventory/code/{Код},
  ///   тело: { "Lines": { "<lineNo>": { "КоличествоФактическое": N, "Действие": "" } } }
  Future<Result<void>> postDocResult(
      String code, Map<int, LineResult> lines) async {
    final path = 'hs/inventory/code/${Uri.encodeComponent(code)}';
    final body = {
      'Lines': {
        for (final e in lines.entries)
          '${e.key}': {
            'КоличествоФактическое': e.value.qty,
            'Действие': e.value.action,
          }
      },
    };
    try {
      await _client.postJson<dynamic>(path, body: body);
      return const Success(null);
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка записи результатов: $e');
      return const Failure(NetworkError());
    }
  }

  /// Получение ФИО аутентифицированного пользователя. STUB.
  /// TODO(1С): уточнить эндпоинт (/me? /whoami?). Сейчас ФИО = логин (не используется).
  Future<String> getCurrentUserFio() async {
    throw UnimplementedError(
        'getCurrentUserFio: эндпоинт уточняется у 1С; сейчас ФИО = логин');
  }
}
