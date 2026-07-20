import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';

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

    test('пустые строки отбрасываются, остальные trim-ятся', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
        (_) async => _jsonResponse<dynamic>(['  A  ', '', '   ', 'B']),
      );
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Монитор');

      expect((res as Success<List<String>>).value, ['A', 'B']);
    });

    test('не-массив → Success([])', () async {
      when(
        () => client.getJson<dynamic>(any()),
      ).thenAnswer((_) async => _jsonResponse<dynamic>({'x': 1}));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getCharacteristics('Монитор');

      expect((res as Success<List<String>>).value, isEmpty);
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
}
