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
  ///
  /// Перебирает несколько способов передачи имени номенклатуры в 1С, потому что
  /// поведение веб-сервера и сама публикация HTTP-сервиса могут отличаться
  /// между базами:
  /// - Apache (как на ERP_Local) безусловно режет `%2F` и `%5C` в path-сегменте
  ///   URL ещё до 1С → для позиций с `/` или `\` GET /invent/{Номенклатура}
  ///   обречён на 404 от Apache. Зато в query-строке (`?Номенклатура=…`) эти
  ///   символы проходят свободно — для этого 1С-сервис должен иметь GET-шаблон
  ///   /invent, читающий `Запрос.ПараметрыЗапроса`. Кириллические ключ и
  ///   значение обязаны быть URL-encoded в UTF-8, причём пробел — как `%20`, а
  ///   не «+»: 1С не декодирует «+» в пробел и не находит номенклатуру. Поэтому
  ///   query формируется вручную через [Uri.encodeComponent] (даёт `%20`), а не
  ///   через параметр `query` Dio (тот кодирует пробел как «+»).
  /// - Рабочая база без обновления 1С имеет только path-шаблон
  ///   /invent/{Номенклатура}; query-шаблона там нет (404).
  ///
  /// Поэтому кандидаты перебираются до первого успеха (порядок важен):
  /// 1. Path с обычным кодированием `/invent/<encodeComponent>` — базовый.
  ///    На рабочей (необновлённой) базе срабатывает для ~99% позиций, так что
  ///    поведение полностью совпадает с прежним — лишних запросов нет.
  /// 2. Query-параметр `/invent?Номенклатура=…` (пробел как %20) — на обновлённой
  ///    базе (Apache) спасает позиции с `/` и `\`, а также берёт обычные, если
  ///    path-шаблон убран целиком (как на ERP_Local).
  /// 3. Path с двойным кодированием route-breaking символов — для серверов,
  ///    декодирующих `%2F`/`%5C` до маршрутизации (запасной сценарий).
  ///
  /// Перебор включается только при «маршрутных» HTTP-ошибках (400/404/500).
  /// Сетевые ошибки (timeout/нет связи) переключают не стратегию, а хост — это
  /// делает существующий failover [DioClient].
  ///
  /// 1С может вернуть JSON-массив строк, одиночную строку или объект с числовыми
  /// ключами. Пустые строки отбрасываются, остальные trim-ятся.
  Future<Result<List<String>>> getCharacteristics(String nomenclature) async {
    final serverValue = _nomenclatureForServer(nomenclature);
    try {
      final res = await _requestCharacteristics(serverValue);
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

  /// Перебирает кандидатов передачи номенклатуры в 1С и возвращает первый
  /// успешный ответ. См. [getCharacteristics] — обоснование порядка попыток.
  Future<Response<dynamic>> _requestCharacteristics(
    String serverValue,
  ) async {
    final encoded = Uri.encodeComponent(serverValue);

    // Порядок важен: path regular первым, чтобы на необновлённой рабочей базе
    // поведение совпадало с прежним (path-шаблон /invent/{Номенклатура}).
    //
    // Query-кандидат формируем вручную (через Uri.encodeComponent) и встраиваем
    // в path, а не через параметр query: Dio кодирует пробелы в query как «+»
    // (form-encoding), а 1С не декодирует «+» в пробел → номенклатура не
    // находится. Uri.encodeComponent даёт %20, который 1С понимает.
    final queryPath =
        'hs/inventory/invent?${Uri.encodeComponent('Номенклатура')}=$encoded';
    final candidates = <Future<Response<dynamic>> Function()>[
      () => _client.getJson<dynamic>('hs/inventory/invent/$encoded'),
      () => _client.getJson<dynamic>(queryPath),
      () => _client.getJson<dynamic>(
        'hs/inventory/invent/${_encodeForDecodedRouter(encoded)}',
      ),
    ];

    DioException? lastError;
    for (var i = 0; i < candidates.length; i++) {
      try {
        return await candidates[i]();
      } on DioException catch (e) {
        // Сетевая ошибка → не пробуем другие стратегии (проблема в связи, а не
        // в кодировании); пусть failover по хостам сработает или ошибка уйдёт.
        if (!_isRouteResolutionError(e) || i == candidates.length - 1) {
          rethrow;
        }
        lastError = e;
        _log.info(
          'Кандидат характеристик #${i + 1} не сработал (${e.response?.statusCode}), '
          'пробую следующий способ кодирования',
        );
      }
    }
    // Не достигается: последняя итерация либо возвращает ответ, либо rethrow.
    throw lastError!;
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
