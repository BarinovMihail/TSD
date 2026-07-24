import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';

import '../domain/barcode_assignment.dart';
import '../domain/doc_table_parser.dart';
import '../domain/doc_table_row.dart';

final _log = Logger('inventory_repository');

/// Запись по строке документа: номер строки → (факт, действие).
typedef LineResult = ({int qty, String action});

/// Табличная часть документа + запись результатов + штрихкоды.
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
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
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

  /// Запись фактических количеств в табличную часть документа 1С.
  /// POST /hs/inventory/updateFact
  ///   тело: {
  ///     "НомерДокумента": "<код>",
  ///     "Строки": [ { "НомерСтроки": N, "КоличествоФактическое": M }, ... ]
  ///   }
  /// Отправляются только строки с ненулевым фактическим количеством
  /// (то, что фактически просканировано).
  Future<Result<void>> postDocResult(
    String code,
    Map<int, LineResult> lines,
  ) async {
    const path = 'hs/inventory/updateFact';
    final body = {
      'НомерДокумента': code,
      'Строки': [
        for (final e in lines.entries)
          if (e.value.qty > 0)
            {'НомерСтроки': e.key, 'КоличествоФактическое': e.value.qty},
      ],
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

  /// Добавить номенклатурную позицию в табличную часть документа.
  /// POST /hs/inventory/newStr.
  Future<Result<void>> addNewLine(
    String docCode,
    String nomenclature,
    String characteristic,
  ) async {
    const path = 'hs/inventory/newStr';
    final body = {
      'НомерДокумента': docCode,
      'Номенклатура': nomenclature,
      'Характеристика': characteristic,
    };
    try {
      await _client.postJson<dynamic>(path, body: body);
      return const Success(null);
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка добавления строки документа: $e');
      return const Failure(NetworkError());
    }
  }

  /// Полный список номенклатурных позиций.
  /// GET /hs/inventory/nomen.
  ///
  /// Принимает JSON-массив либо объект с числовыми ключами (типичный формат
  /// 1С). Элементом может быть строка или объект с полем «Номенклатура» /
  /// «Наименование».
  Future<Result<List<String>>> getNomenclatures() async {
    const path = 'hs/inventory/nomen';
    try {
      final res = await _client.getJson<dynamic>(path);
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      final Iterable<dynamic> items;
      if (data is List) {
        items = data;
      } else if (data is Map) {
        items = data.values;
      } else {
        return const Failure(
          ParseError('Ожидался список номенклатурных позиций'),
        );
      }

      final result = <String>[];
      final seen = <String>{};
      for (final item in items) {
        final String value;
        if (item is Map) {
          value =
              (item['Номенклатура'] ??
                      item['Наименование'] ??
                      item['НоменклатураНаименование'])
                  ?.toString()
                  .trim() ??
              '';
        } else {
          value = item?.toString().trim() ?? '';
        }
        if (value.isNotEmpty && seen.add(value)) result.add(value);
      }
      result.sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
      return Success(result);
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка получения списка номенклатуры: $e');
      return const Failure(
        ParseError('Не удалось разобрать список номенклатурных позиций'),
      );
    }
  }

  /// Список характеристик выбранной номенклатуры.
  /// GET /hs/inventory/invent/{Номенклатура} (Номенклатура URL-encoded).
  /// 1С возвращает JSON-массив строк: ["21,5\" AOC №…", ...].
  /// Пустые строки отбрасываются, остальные trim-ятся.
  Future<Result<List<String>>> getCharacteristics(String nomenclature) async {
    final path = 'hs/inventory/invent/${Uri.encodeComponent(nomenclature)}';
    try {
      final res = await _client.getJson<dynamic>(path);
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      if (data is! List) return const Success([]);
      final result = <String>[];
      for (final item in data) {
        final c = item?.toString().trim() ?? '';
        if (c.isNotEmpty) result.add(c);
      }
      return Success(result);
    } on DioException catch (e) {
      // HTTP 404 — это не ошибка загрузки, а отсутствие характеристик.
      // Сюда попадают в т.ч. номенклатуры со спецсимволами (например «/»),
      // из-за которых веб-сервер перед 1С режет %2F и рвёт маршрут: 1С их не
      // находит, и добавление штрихкода оказывалось полностью заблокировано.
      // Запись штрихкода идёт POST-ом в теле JSON (символы в названии там не
      // мешают), поэтому отдаём пустой список и не блокируем диалог.
      if (e.response?.statusCode == 404) return const Success([]);
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка получения характеристик: $e');
      return const Failure(
        ParseError('Не удалось разобрать список характеристик'),
      );
    }
  }

  /// Добавление первого или дополнительного штрихкода позиции в 1С.
  /// POST /hs/inventory/newBarcode
  ///   тело: { "Номенклатура": "<наименование>", "Характеристика": "<текст>" }
  /// «Без характеристики» → пустая строка ("Характеристика": "").
  /// Формат ответа 1С не предполагается: новый штрихкод и состояние иконки
  /// получаются повторной загрузкой документа через [getTable].
  ///
  /// Запрос может быть тяжёлым (1С генерирует/записывает штрихкод, особенно для
  /// номенклатур со сложной структурой), поэтому per-request receiveTimeout
  /// увеличен до 120с. Иначе дефолтный таймаут даёт ложный NetworkError, хотя
  /// 1С фактически успевает записать штрихкод (он виден после обновления).
  Future<Result<void>> addBarcode(
    String nomenclature,
    String characteristic,
  ) => _addBarcode(nomenclature, characteristic);

  /// Привязка уже существующего штрихкода с упаковки к позиции в 1С.
  /// Использует тот же POST /newBarcode, но дополнительно передаёт поле
  /// «Штрихкод». При его наличии 1С не генерирует новый EAN-13.
  Future<Result<void>> addScannedBarcode(
    String nomenclature,
    String characteristic,
    String barcode,
  ) => _addBarcode(nomenclature, characteristic, barcode: barcode.trim());

  /// Удаление штрихкода в 1С по его номеру.
  /// DELETE /hs/inventory/delete/{Штрихкод} (номер URL-encoded).
  /// Успешный ответ:
  /// {"Штрихкод":"...", "Результат":"Успешно удалено"}.
  Future<Result<void>> deleteBarcode(String barcode) async {
    final normalized = barcode.trim();
    final path = 'hs/inventory/delete/${Uri.encodeComponent(normalized)}';
    try {
      final response = await _client.deleteJson<dynamic>(path);
      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (data is! Map ||
          data['Штрихкод']?.toString().trim() != normalized ||
          data['Результат']?.toString().trim() != 'Успешно удалено') {
        return const Failure(
          ParseError('Некорректный ответ сервиса удаления штрихкода'),
        );
      }
      return const Success(null);
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка удаления штрихкода: $e');
      return const Failure(NetworkError());
    }
  }

  /// Текущая привязка штрихкода в 1С.
  /// GET /hs/inventory/barcode/{Штрихкод}.
  ///
  /// Пустой объект или ответ с пустым наименованием означает, что штрихкод
  /// ещё свободен.
  /// Для совместимости принимаются поля «Номенклатура» и «Наименование».
  Future<Result<BarcodeAssignment?>> getBarcodeAssignment(
    String barcode,
  ) async {
    final normalized = barcode.trim();
    final path = 'hs/inventory/barcode/${Uri.encodeComponent(normalized)}';
    try {
      final response = await _client.getJson<dynamic>(path);
      final dynamic data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (data is! Map) {
        return const Failure(
          ParseError('Некорректный ответ сервиса поиска штрихкода'),
        );
      }

      final nomenclature =
          (data['Номенклатура'] ??
                  data['Наименование'] ??
                  data['НоменклатураНаименование'])
              ?.toString()
              .trim() ??
          '';
      if (nomenclature.isEmpty) return const Success(null);
      final characteristic =
          data['Характеристика']?.toString().trim() ?? '';
      return Success(
        BarcodeAssignment(
          nomenclature: nomenclature,
          characteristic: characteristic,
        ),
      );
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка поиска штрихкода: $e');
      return const Failure(
        ParseError('Не удалось разобрать текущую привязку штрихкода'),
      );
    }
  }

  Future<Result<void>> _addBarcode(
    String nomenclature,
    String characteristic, {
    String? barcode,
  }) async {
    const path = 'hs/inventory/newBarcode';
    final body = {
      'Номенклатура': nomenclature,
      'Характеристика': characteristic,
      if (barcode != null) 'Штрихкод': barcode,
    };
    try {
      await _client.postJson<dynamic>(
        path,
        body: body,
        receiveTimeout: const Duration(seconds: 120),
      );
      return const Success(null);
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка добавления штрихкода: $e');
      return const Failure(NetworkError());
    }
  }

  /// Получение ФИО аутентифицированного пользователя. STUB.
  /// TODO(1С): уточнить эндпоинт (/me? /whoami?). Сейчас ФИО = логин (не используется).
  Future<String> getCurrentUserFio() async {
    throw UnimplementedError(
      'getCurrentUserFio: эндпоинт уточняется у 1С; сейчас ФИО = логин',
    );
  }
}
