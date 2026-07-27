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
  final Map<String, String> _nomenclatureServerValues = {};

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
      'Номенклатура': _nomenclatureForServer(nomenclature),
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
      } else if (data is Map &&
          data.keys.every((key) => int.tryParse(key.toString()) != null)) {
        items = data.values;
      } else {
        return const Failure(
          ParseError('Ожидался список номенклатурных позиций'),
        );
      }

      final result = <String>[];
      final seen = <String>{};
      final serverValues = <String, String>{};
      for (final item in items) {
        final String rawValue;
        if (item is Map) {
          rawValue =
              (item['Номенклатура'] ??
                      item['Наименование'] ??
                      item['НоменклатураНаименование'])
                  ?.toString() ??
              '';
        } else {
          rawValue = item?.toString() ?? '';
        }
        final value = _nomenclatureDisplayValue(rawValue);
        if (value.isNotEmpty && seen.add(value)) {
          result.add(value);
          serverValues[value] = rawValue;
        }
      }
      result.sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
      _nomenclatureServerValues
        ..clear()
        ..addAll(serverValues);
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
  /// 1С может вернуть JSON-массив строк, одиночную строку или объект
  /// с числовыми ключами.
  /// Пустые строки отбрасываются, остальные trim-ятся.
  Future<Result<List<String>>> getCharacteristics(String nomenclature) async {
    final serverValue = _nomenclatureForServer(nomenclature);
    final encoded = Uri.encodeComponent(serverValue);
    final path = 'hs/inventory/invent/$encoded';
    try {
      final res = await _getCharacteristicsResponse(
        path: path,
        encodedNomenclature: encoded,
      );
      final data = res.data is String
          ? jsonDecode(res.data as String)
          : res.data;
      final Iterable<dynamic> items;
      if (data is List) {
        items = data;
      } else if (data is Map &&
          data.keys.every((key) => int.tryParse(key.toString()) != null)) {
        items = data.values;
      } else if (data is String || data is num) {
        items = [data];
      } else {
        return const Failure(
          ParseError('Некорректный ответ списка характеристик'),
        );
      }
      final result = <String>[];
      final seen = <String>{};
      for (final item in items) {
        final c = item?.toString().trim() ?? '';
        if (c.isNotEmpty && seen.add(c)) result.add(c);
      }
      return Success(result);
    } on DioException catch (e) {
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
      'Номенклатура': _nomenclatureForServer(nomenclature),
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

  /// Возвращает исходное значение ровно в том виде, в котором его прислала 1С.
  ///
  /// В интерфейсе управляющие символы заменяются пробелами, а внешние пробелы
  /// скрываются. Для запросов они значимы, поэтому храним исходное значение
  /// отдельно от отображаемого.
  String _nomenclatureForServer(String value) =>
      _nomenclatureServerValues[value] ?? value;

  /// Делает название безопасным для отображения одной строкой, не изменяя
  /// обычные внутренние пробелы (в 1С есть разные позиции с одним и двумя
  /// пробелами).
  static String _nomenclatureDisplayValue(String value) => value
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .trim();

  /// Некоторые web-серверы декодируют URL до передачи маршрута в 1С. Тогда
  /// `%2F` снова становится `/` и разрывает параметр `{Номенклатура}` на два
  /// сегмента. Сначала используем обычное URL-кодирование. Если маршрутизатор
  /// отвечает ошибкой, повторяем запрос, оставляя опасные символы
  /// закодированными после первого декодирования.
  Future<Response<dynamic>> _getCharacteristicsResponse({
    required String path,
    required String encodedNomenclature,
  }) async {
    try {
      return await _client.getJson<dynamic>(path);
    } on DioException catch (error) {
      final fallbackEncoded = _encodeForDecodedRouter(encodedNomenclature);
      if (!_isRouteResolutionError(error) ||
          fallbackEncoded == encodedNomenclature) {
        rethrow;
      }
      _log.info(
        'Повторный запрос характеристик с защищённым URL-параметром',
      );
      return _client.getJson<dynamic>(
        'hs/inventory/invent/$fallbackEncoded',
      );
    }
  }

  static bool _isRouteResolutionError(DioException error) {
    final status = error.response?.statusCode;
    return status == 400 || status == 404 || status == 500;
  }

  /// Двойное кодирование применяется только к символам, способным изменить
  /// структуру URL после преждевременного декодирования: /, \, ?, #, %,
  /// управляющим ASCII-символам и значимым пробелам на краях. Остальная строка
  /// остаётся обычным encoded path segment.
  static String _encodeForDecodedRouter(String encoded) {
    final routeBreakingEscape = RegExp(
      r'%(?:0[0-9A-F]|1[0-9A-F]|23|25|2F|3F|5C|7F)',
      caseSensitive: false,
    );
    var result = encoded.replaceAllMapped(
      routeBreakingEscape,
      (match) => '%25${match.group(0)!.substring(1).toUpperCase()}',
    );
    final edgeSpaces = [
      RegExp(r'^(?:%20)+', caseSensitive: false),
      RegExp(r'(?:%20)+$', caseSensitive: false),
    ];
    for (final pattern in edgeSpaces) {
      result = result.replaceAllMapped(
        pattern,
        (match) => match.group(0)!.replaceAll('%', '%25'),
      );
    }
    return result;
  }

  /// Получение ФИО аутентифицированного пользователя. STUB.
  /// TODO(1С): уточнить эндпоинт (/me? /whoami?). Сейчас ФИО = логин (не используется).
  Future<String> getCurrentUserFio() async {
    throw UnimplementedError(
      'getCurrentUserFio: эндпоинт уточняется у 1С; сейчас ФИО = логин',
    );
  }
}
