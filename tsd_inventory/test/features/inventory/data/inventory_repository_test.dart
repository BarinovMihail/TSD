import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_assignment.dart';

class _MockClient extends Mock implements DioClient {}

class _MockDb extends Mock implements AppDatabase {}

/// Заглушка ответа dio, возвращаемая из мока DioClient.postJson.
Response<T> _okResponse<T>() =>
    Response<T>(requestOptions: RequestOptions(path: ''), statusCode: 200);

/// Заглушка GET-ответа с JSON-данными.
Response<T> _jsonResponse<T>(Object data) => Response<T>(
  requestOptions: RequestOptions(path: ''),
  statusCode: 200,
  data: data as T,
);

/// Строит путь запроса характеристик через query-параметр ровно так же, как
/// InventoryRepository._requestCharacteristics: ключ и значение кодируются
/// Uri.encodeComponent (пробел → %20, а не «+», как сделал бы Dio). Обёртка
/// нужна, чтобы тесты не дублировать логику формирования и не расходиться с
/// реализацией.
String _characteristicsQueryPath(String nomenclature) =>
    'hs/inventory/invent?${Uri.encodeComponent('Номенклатура')}'
    '=${Uri.encodeComponent(nomenclature)}';

void main() {
  late _MockClient client;
  late _MockDb db;

  setUp(() {
    client = _MockClient();
    db = _MockDb();
    registerFallbackValue('');
  });

  group('postDocResult — формат запроса к 1С', () {
    test(
      'тело: НомерДокумента + Строки[] с НомерСтроки/КоличествоФактическое',
      () async {
        when(
          () => client.postJson<dynamic>(any(), body: any(named: 'body')),
        ).thenAnswer((_) async => _okResponse<dynamic>());
        final repo = InventoryRepository(client: client, db: db);

        final res = await repo.postDocResult('АЕ-00000002', {
          1: (qty: 7, action: ''),
          2: (qty: 9, action: ''),
        });

        expect(res, isA<Success>());
        final body = verify(
          () => client.postJson<dynamic>(
            captureAny(),
            body: captureAny(named: 'body'),
          ),
        ).captured;
        // путь
        expect(body[0], 'hs/inventory/updateFact');
        // тело — точно по контракту 1С
        expect(body[1], {
          'НомерДокумента': 'АЕ-00000002',
          'Строки': [
            {'НомерСтроки': 1, 'КоличествоФактическое': 7},
            {'НомерСтроки': 2, 'КоличествоФактическое': 9},
          ],
        });
      },
    );

    test('строки с нулевым фактом не отправляются', () async {
      when(
        () => client.postJson<dynamic>(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      await repo.postDocResult('АЕ-1', {
        1: (qty: 5, action: ''),
        2: (qty: 0, action: ''), // не отсканировано
        3: (qty: 2, action: ''),
      });

      final captured =
          verify(
                () => client.postJson<dynamic>(
                  any(),
                  body: captureAny(named: 'body'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      final rows = captured['Строки'] as List;
      expect(rows.length, 2); // только строки 1 и 3
      expect(
        rows,
        containsAll(<Map<String, int>>[
          {'НомерСтроки': 1, 'КоличествоФактическое': 5},
          {'НомерСтроки': 3, 'КоличествоФактическое': 2},
        ]),
      );
      expect(rows.any((r) => r['НомерСтроки'] == 2), isFalse);
    });

    test('ничего не отсканировано → пустой массив Строк', () async {
      when(
        () => client.postJson<dynamic>(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      await repo.postDocResult('АЕ-1', {
        1: (qty: 0, action: ''),
        2: (qty: 0, action: ''),
      });

      final captured =
          verify(
                () => client.postJson<dynamic>(
                  any(),
                  body: captureAny(named: 'body'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['НомерДокумента'], 'АЕ-1');
      expect(captured['Строки'], isEmpty);
    });

    test('сетевая ошибка Dio → Failure', () async {
      when(
        () => client.postJson<dynamic>(any(), body: any(named: 'body')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.postDocResult('АЕ-1', {1: (qty: 1, action: '')});

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });
  });

  group('addNewLine — добавление позиции в документ', () {
    test('POST /newStr с документом, номенклатурой и характеристикой', () async {
      when(
        () => client.postJson<dynamic>(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.addNewLine(
        'АЕ-1',
        'Клавиатура',
        'Белая',
      );

      expect(result, isA<Success<void>>());
      final captured = verify(
        () => client.postJson<dynamic>(
          captureAny(),
          body: captureAny(named: 'body'),
        ),
      ).captured;
      expect(captured[0], 'hs/inventory/newStr');
      expect(captured[1], {
        'НомерДокумента': 'АЕ-1',
        'Номенклатура': 'Клавиатура',
        'Характеристика': 'Белая',
      });
    });

    test('использует исходное имя позиции из ответа /nomen', () async {
      when(
        () => client.getJson<dynamic>('hs/inventory/nomen'),
      ).thenAnswer(
        (_) async => _jsonResponse<dynamic>(['Фреза\t20.1660-50']),
      );
      when(
        () => client.postJson<dynamic>(any(), body: any(named: 'body')),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);
      await repo.getNomenclatures();

      await repo.addNewLine('АЕ-1', 'Фреза 20.1660-50', '-');

      final body =
          verify(
                () => client.postJson<dynamic>(
                  'hs/inventory/newStr',
                  body: captureAny(named: 'body'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['Номенклатура'], 'Фреза\t20.1660-50');
    });
  });

  group('getNomenclatures — полный список номенклатуры', () {
    test('GET /nomen, trim, дедупликация и сортировка', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
        (_) async => _jsonResponse<dynamic>([
          '  Принтер ',
          'Монитор',
          '',
          'Монитор',
        ]),
      );
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.getNomenclatures();

      expect(result, isA<Success<List<String>>>());
      expect((result as Success<List<String>>).value, ['Монитор', 'Принтер']);
      verify(() => client.getJson<dynamic>('hs/inventory/nomen')).called(1);
    });

    test('принимает строковый JSON, объект 1С и поля с наименованием', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
        (_) async => _jsonResponse<dynamic>(
          jsonEncode({
            '1': {'Номенклатура': 'Монитор'},
            '2': {'Наименование': 'Клавиатура'},
            '3': {'НоменклатураНаименование': 'Мышь'},
          }),
        ),
      );
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.getNomenclatures();

      expect((result as Success<List<String>>).value, [
        'Клавиатура',
        'Монитор',
        'Мышь',
      ]);
    });

    test('ответ не в виде списка или объекта → Failure(ParseError)', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
        (_) async => _jsonResponse<dynamic>(42),
      );
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.getNomenclatures();

      expect(result, isA<Failure<List<String>>>());
      expect((result as Failure<List<String>>).error, isA<ParseError>());
    });

    test(
      'скрывает управляющие и внешние пробелы, но отправляет в 1С исходное имя',
      () async {
        when(
          () => client.getJson<dynamic>('hs/inventory/nomen'),
        ).thenAnswer(
          (_) async => _jsonResponse<dynamic>([
            'Бор Фрезы ',
            'Фреза\t20.1660-50',
          ]),
        );
        when(
          () => client.getJson<dynamic>(
            'hs/inventory/invent/${Uri.encodeComponent('Бор Фрезы ')}',
          ),
        ).thenAnswer((_) async => _jsonResponse<dynamic>(<String>[]));
        final repo = InventoryRepository(client: client, db: db);

        final nomenclatures = await repo.getNomenclatures();
        final characteristics = await repo.getCharacteristics('Бор Фрезы');

        expect((nomenclatures as Success<List<String>>).value, [
          'Бор Фрезы',
          'Фреза 20.1660-50',
        ]);
        expect(characteristics, isA<Success<List<String>>>());
        verify(
          () => client.getJson<dynamic>(
            'hs/inventory/invent/${Uri.encodeComponent('Бор Фрезы ')}',
          ),
        ).called(1);
      },
    );
  });

  group('getCharacteristics — список характеристик номенклатуры', () {
    test(
      'путь hs/inventory/invent/{nomenclature}, парсинг массива строк',
      () async {
        when(() => client.getJson<dynamic>(any())).thenAnswer(
          (_) async => _jsonResponse<dynamic>([
            '21,5" AOC №GCXFAHA005080',
            '21,5" AOC №GGMH6HA022400',
          ]),
        );
        final repo = InventoryRepository(client: client, db: db);

        final res = await repo.getCharacteristics('Монитор АОС 21,5');

        expect(res, isA<Success>());
        expect((res as Success<List<String>>).value, [
          '21,5" AOC №GCXFAHA005080',
          '21,5" AOC №GGMH6HA022400',
        ]);
        // Номенклатура кодируется в URL.
        verify(
          () => client.getJson<dynamic>(
            'hs/inventory/invent/${Uri.encodeComponent('Монитор АОС 21,5')}',
          ),
        ).called(1);
      },
    );

    test('пустой список характеристик → Success([])', () async {
      when(
        () => client.getJson<dynamic>(any()),
      ).thenAnswer((_) async => _jsonResponse<dynamic>(<String>[]));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Монитор');

      expect(res, isA<Success>());
      expect((res as Success<List<String>>).value, isEmpty);
    });

    test('принимает строковый JSON', () async {
      when(
        () => client.getJson<dynamic>(any()),
      ).thenAnswer((_) async => _jsonResponse<dynamic>(jsonEncode(['A', 'B'])));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Монитор');

      expect((res as Success<List<String>>).value, ['A', 'B']);
    });

    test('принимает единственную характеристику строкой, включая «-»', () async {
      when(
        () => client.getJson<dynamic>(any()),
      ).thenAnswer((_) async => _jsonResponse<dynamic>(jsonEncode('-')));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Седло');

      expect((res as Success<List<String>>).value, ['-']);
    });

    test('принимает объект с числовыми ключами как массив 1С', () async {
      when(
        () => client.getJson<dynamic>(any()),
      ).thenAnswer(
        (_) async => _jsonResponse<dynamic>({'0': '-', '1': 'Красное'}),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Седло');

      expect((res as Success<List<String>>).value, ['-', 'Красное']);
    });

    test('пустые строки отбрасываются, остальные trim-ятся', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
        (_) async => _jsonResponse<dynamic>(['  A  ', '', '   ', 'B']),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Монитор');

      expect((res as Success<List<String>>).value, ['A', 'B']);
    });

    test('неожиданный объект → Failure(ParseError)', () async {
      when(
        () => client.getJson<dynamic>(any()),
      ).thenAnswer((_) async => _jsonResponse<dynamic>({'x': 1}));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Монитор');

      expect(res, isA<Failure<List<String>>>());
      expect((res as Failure<List<String>>).error, isA<ParseError>());
    });

    test('сетевая ошибка Dio → Failure(NetworkError)', () async {
      when(() => client.getJson<dynamic>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Монитор');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });

    test(
      'HTTP 404 не подменяется отсутствием характеристик',
      () async {
        // Все кандидаты (path regular, query-in-path, double-encoded) вызываются
        // через getJson(path) с query=null и падают с 404.
        when(() => client.getJson<dynamic>(any())).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: ''),
            response: Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 404,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        final repo = InventoryRepository(client: client, db: db);

        final res = await repo.getCharacteristics('яяя_Удлинитель/10.9/');

        expect(res, isA<Failure<List<String>>>());
        expect((res as Failure<List<String>>).error, isA<NotFoundError>());
      },
    );

    test(
      'path regular первый: на необновлённой базе срабатывает сразу (как раньше)',
      () async {
        // Рабочая база без правки 1С: path-шаблон /invent/{...} есть, query нет.
        // Path regular должен сработать с первого раза — поведение как прежде,
        // лишний запрос к query не делается.
        const nomenclature = 'МФУ Kyocera 10/9';
        final encoded = Uri.encodeComponent(nomenclature);
        when(
          () => client.getJson<dynamic>('hs/inventory/invent/$encoded'),
        ).thenAnswer((_) async => _jsonResponse<dynamic>(['-']));
        final repo = InventoryRepository(client: client, db: db);

        final result = await repo.getCharacteristics(nomenclature);

        expect((result as Success<List<String>>).value, ['-']);
        verify(
          () => client.getJson<dynamic>('hs/inventory/invent/$encoded'),
        ).called(1);
        // query-кандидат не звался — path regular сработал с первого раза.
        verifyNever(
          () => client.getJson<dynamic>(_characteristicsQueryPath(nomenclature)),
        );
      },
    );

    test(
      'имя со слэшем: path 404 (Apache режет %2F) → query успех',
      () async {
        // Обновлённая база (Apache): path regular падает (404 от Apache для %2F),
        // query-параметр пропускает %2F и возвращает характеристики.
        const nomenclature = 'МФУ Kyocera 10/9';
        final encoded = Uri.encodeComponent(nomenclature);
        final regularPath = 'hs/inventory/invent/$encoded';
        final queryPath = _characteristicsQueryPath(nomenclature);
        when(
          () => client.getJson<dynamic>(regularPath),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: regularPath),
            response: Response<void>(
              requestOptions: RequestOptions(path: regularPath),
              statusCode: 404,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        when(
          () => client.getJson<dynamic>(queryPath),
        ).thenAnswer((_) async => _jsonResponse<dynamic>(['-']));
        final repo = InventoryRepository(client: client, db: db);

        final result = await repo.getCharacteristics(nomenclature);

        expect((result as Success<List<String>>).value, ['-']);
        verify(() => client.getJson<dynamic>(regularPath)).called(1);
        verify(() => client.getJson<dynamic>(queryPath)).called(1);
      },
    );

    test(
      'имя с обратным слэшем: path 404 (Apache режет %5C) → query успех',
      () async {
        // %5C в path режется Apache так же, как %2F; query спасает.
        const nomenclature = r'Манометр МП4-УУ2 0-250кгс\см2';
        final encoded = Uri.encodeComponent(nomenclature);
        final queryPath = _characteristicsQueryPath(nomenclature);
        when(
          () => client.getJson<dynamic>('hs/inventory/invent/$encoded'),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: 'hs/inventory/invent/$encoded'),
            response: Response<void>(
              requestOptions: RequestOptions(path: 'hs/inventory/invent/$encoded'),
              statusCode: 404,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        when(
          () => client.getJson<dynamic>(queryPath),
        ).thenAnswer((_) async => _jsonResponse<dynamic>(['-']));
        final repo = InventoryRepository(client: client, db: db);

        final result = await repo.getCharacteristics(nomenclature);

        expect((result as Success<List<String>>).value, ['-']);
        verify(() => client.getJson<dynamic>(queryPath)).called(1);
      },
    );

    test(
      'запасной сценарий: path 404 → query 404 → path double-encoded успех',
      () async {
        // Сервер декодирует %2F повторно: path regular режется, query-шаблона
        // нет, но двойное кодирование %252F спасает.
        const nomenclature = 'МФУ Kyocera 10/9';
        final encoded = Uri.encodeComponent(nomenclature);
        final regularPath = 'hs/inventory/invent/$encoded';
        final queryPath = _characteristicsQueryPath(nomenclature);
        final protectedPath =
            'hs/inventory/invent/${encoded.replaceAll('%2F', '%252F')}';
        when(
          () => client.getJson<dynamic>(regularPath),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: regularPath),
            response: Response<void>(
              requestOptions: RequestOptions(path: regularPath),
              statusCode: 404,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        when(
          () => client.getJson<dynamic>(queryPath),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: queryPath),
            response: Response<void>(
              requestOptions: RequestOptions(path: queryPath),
              statusCode: 404,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        when(
          () => client.getJson<dynamic>(protectedPath),
        ).thenAnswer((_) async => _jsonResponse<dynamic>(['-']));
        final repo = InventoryRepository(client: client, db: db);

        final result = await repo.getCharacteristics(nomenclature);

        expect((result as Success<List<String>>).value, ['-']);
        verify(() => client.getJson<dynamic>(regularPath)).called(1);
        verify(() => client.getJson<dynamic>(queryPath)).called(1);
        verify(() => client.getJson<dynamic>(protectedPath)).called(1);
      },
    );

    test(
      'защищает значимый пробел в конце исходного имени',
      () async {
        // Между path regular и double-encoded теперь есть query-кандидат;
        // мокаем его 404, чтобы проверить, что fallback доходит до
        // double-encoded, защищающего краевой пробел (%20 → %2520).
        when(
          () => client.getJson<dynamic>('hs/inventory/nomen'),
        ).thenAnswer((_) async => _jsonResponse<dynamic>(['Бор Фрезы ']));
        const serverValue = 'Бор Фрезы ';
        final regularPath =
            'hs/inventory/invent/${Uri.encodeComponent(serverValue)}';
        final queryPath = _characteristicsQueryPath(serverValue);
        final protectedPath =
            'hs/inventory/invent/${Uri.encodeComponent('Бор Фрезы')}%2520';
        when(
          () => client.getJson<dynamic>(regularPath),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: regularPath),
            response: Response<void>(
              requestOptions: RequestOptions(path: regularPath),
              statusCode: 404,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        when(
          () => client.getJson<dynamic>(queryPath),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: queryPath),
            response: Response<void>(
              requestOptions: RequestOptions(path: queryPath),
              statusCode: 404,
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        when(
          () => client.getJson<dynamic>(protectedPath),
        ).thenAnswer((_) async => _jsonResponse<dynamic>(['-']));
        final repo = InventoryRepository(client: client, db: db);
        await repo.getNomenclatures();

        final result = await repo.getCharacteristics('Бор Фрезы');

        expect((result as Success<List<String>>).value, ['-']);
        verify(() => client.getJson<dynamic>(regularPath)).called(1);
        verify(() => client.getJson<dynamic>(queryPath)).called(1);
        verify(() => client.getJson<dynamic>(protectedPath)).called(1);
      },
    );

    test('HTTP 500 по-прежнему → Failure(ServerError)', () async {
      when(() => client.getJson<dynamic>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          response: Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 500,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Монитор');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ServerError>());
    });
  });

  group('addBarcode — добавление штрихкода в 1С', () {
    test('тело: Номенклатура + Характеристика, путь newBarcode', () async {
      when(
        () => client.postJson<dynamic>(
          any(),
          body: any(named: 'body'),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.addBarcode(
        'Монитор',
        '23,5" Samsung №CWGCH4ZR503628',
      );

      expect(res, isA<Success>());
      final captured = verify(
        () => client.postJson<dynamic>(
          captureAny(),
          body: captureAny(named: 'body'),
          receiveTimeout: captureAny(named: 'receiveTimeout'),
        ),
      ).captured;
      // captured = [path, body, receiveTimeout]
      expect(captured[0], 'hs/inventory/newBarcode');
      expect(captured[1], {
        'Номенклатура': 'Монитор',
        'Характеристика': '23,5" Samsung №CWGCH4ZR503628',
      });
    });

    test('использует исходное имя позиции из ответа /nomen', () async {
      when(
        () => client.getJson<dynamic>('hs/inventory/nomen'),
      ).thenAnswer((_) async => _jsonResponse<dynamic>(['Бор Фрезы ']));
      when(
        () => client.postJson<dynamic>(
          any(),
          body: any(named: 'body'),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);
      await repo.getNomenclatures();

      await repo.addBarcode('Бор Фрезы', '-');

      final body =
          verify(
                () => client.postJson<dynamic>(
                  'hs/inventory/newBarcode',
                  body: captureAny(named: 'body'),
                  receiveTimeout: any(named: 'receiveTimeout'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['Номенклатура'], 'Бор Фрезы ');
    });

    test('передаёт увеличенный receiveTimeout (тяжёлая операция 1С)', () async {
      when(
        () => client.postJson<dynamic>(
          any(),
          body: any(named: 'body'),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      await repo.addBarcode('Монитор', 'Black');

      final captured = verify(
        () => client.postJson<dynamic>(
          any(),
          body: any(named: 'body'),
          receiveTimeout: captureAny(named: 'receiveTimeout'),
        ),
      ).captured;
      final timeout = captured.whereType<Duration>().single;
      expect(timeout, const Duration(seconds: 120));
    });

    test('«Без характеристики» → пустая строка', () async {
      when(
        () => client.postJson<dynamic>(
          any(),
          body: any(named: 'body'),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      await repo.addBarcode('Монитор', '');

      final captured = verify(
        () => client.postJson<dynamic>(
          captureAny(),
          body: captureAny(named: 'body'),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).captured;
      // captured = [path, body]
      expect(captured[0], 'hs/inventory/newBarcode');
      expect((captured[1] as Map<String, dynamic>)['Характеристика'], '');
    });

    test('отсканированный ШК передаётся в том же запросе', () async {
      when(
        () => client.postJson<dynamic>(
          any(),
          body: any(named: 'body'),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.addScannedBarcode(
        'Монитор',
        'Black',
        ' 0012345678905 ',
      );

      expect(res, isA<Success>());
      final captured = verify(
        () => client.postJson<dynamic>(
          captureAny(),
          body: captureAny(named: 'body'),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).captured;
      expect(captured[0], 'hs/inventory/newBarcode');
      expect(captured[1], {
        'Номенклатура': 'Монитор',
        'Характеристика': 'Black',
        'Штрихкод': '0012345678905',
      });
    });

    test('сетевая ошибка Dio → Failure', () async {
      when(
        () => client.postJson<dynamic>(
          any(),
          body: any(named: 'body'),
          receiveTimeout: any(named: 'receiveTimeout'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.addBarcode('Монитор', 'Black');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });
  });

  group('getBarcodeAssignment — GET /barcode/{ШК}', () {
    test('URL-кодирует ШК и разбирает номенклатуру с характеристикой', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
        (_) async => _jsonResponse<dynamic>({
          'Номенклатура': ' Монитор ',
          'Характеристика': ' Black ',
        }),
      );
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.getBarcodeAssignment(' ШК 12/34 ');

      expect(result, isA<Success<BarcodeAssignment?>>());
      final assignment = (result as Success<BarcodeAssignment?>).value;
      expect(assignment?.nomenclature, 'Монитор');
      expect(assignment?.characteristic, 'Black');
      verify(
        () => client.getJson<dynamic>(
          'hs/inventory/barcode/%D0%A8%D0%9A%2012%2F34',
        ),
      ).called(1);
    });

    test('принимает поле «Наименование» и строковый JSON', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
        (_) async => _jsonResponse<dynamic>(
          jsonEncode({'Наименование': 'Клавиатура', 'Характеристика': ''}),
        ),
      );
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.getBarcodeAssignment('123');

      final assignment = (result as Success<BarcodeAssignment?>).value;
      expect(assignment?.nomenclature, 'Клавиатура');
      expect(assignment?.characteristic, '');
    });

    test('пустой объект означает, что ШК свободен', () async {
      when(
        () => client.getJson<dynamic>(any()),
      ).thenAnswer((_) async => _jsonResponse<dynamic>(<String, dynamic>{}));
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.getBarcodeAssignment('123');

      expect((result as Success<BarcodeAssignment?>).value, isNull);
    });

    test('404 не считается свободным ШК и блокирует добавление', () async {
      when(() => client.getJson<dynamic>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          response: Response<void>(
            requestOptions: RequestOptions(path: ''),
            statusCode: 404,
          ),
        ),
      );
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.getBarcodeAssignment('123');

      expect(result, isA<Failure<BarcodeAssignment?>>());
      expect((result as Failure).error, isA<NotFoundError>());
    });

    test('некорректный ответ блокирует добавление', () async {
      when(
        () => client.getJson<dynamic>(any()),
      ).thenAnswer((_) async => _jsonResponse<dynamic>('not-json'));
      final repo = InventoryRepository(client: client, db: db);

      final result = await repo.getBarcodeAssignment('123');

      expect(result, isA<Failure<BarcodeAssignment?>>());
      expect((result as Failure).error, isA<ParseError>());
    });
  });

  group('deleteBarcode — DELETE /delete/{ШК}', () {
    test('номер штрихкода trim-ится и URL-кодируется', () async {
      when(
        () => client.deleteJson<dynamic>(any()),
      ).thenAnswer(
        (_) async => _jsonResponse<dynamic>({
          'Штрихкод': 'ШК 12/34',
          'Результат': 'Успешно удалено',
        }),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.deleteBarcode(' ШК 12/34 ');

      expect(res, isA<Success>());
      verify(
        () => client.deleteJson<dynamic>(
          'hs/inventory/delete/%D0%A8%D0%9A%2012%2F34',
        ),
      ).called(1);
    });

    test('проверяет результат из JSON-ответа', () async {
      when(
        () => client.deleteJson<dynamic>(any()),
      ).thenAnswer(
        (_) async => _jsonResponse<dynamic>({
          'Штрихкод': '0012345678905',
          'Результат': 'Не удалено',
        }),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.deleteBarcode('0012345678905');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ParseError>());
    });

    test('сетевая ошибка Dio → Failure', () async {
      when(() => client.deleteJson<dynamic>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.deleteBarcode('0012345678905');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });
  });
}
