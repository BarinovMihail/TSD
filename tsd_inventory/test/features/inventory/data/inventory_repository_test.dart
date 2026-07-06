import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_info.dart';

class _MockClient extends Mock implements DioClient {}

class _MockDb extends Mock implements AppDatabase {}

/// Заглушка ответа dio, возвращаемая из мока DioClient.postJson.
Response<T> _okResponse<T>() => Response<T>(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
    );

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
    test('тело: НомерДокумента + Строки[] с НомерСтроки/КоличествоФактическое',
        () async {
      when(() => client.postJson<dynamic>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.postDocResult(
        'АЕ-00000002',
        {
          1: (qty: 7, action: ''),
          2: (qty: 9, action: ''),
        },
      );

      expect(res, isA<Success>());
      final body = verify(() => client.postJson<dynamic>(captureAny(),
              body: captureAny(named: 'body')))
          .captured;
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
    });

    test('строки с нулевым фактом не отправляются', () async {
      when(() => client.postJson<dynamic>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      await repo.postDocResult('АЕ-1', {
        1: (qty: 5, action: ''),
        2: (qty: 0, action: ''), // не отсканировано
        3: (qty: 2, action: ''),
      });

      final captured = verify(() => client.postJson<dynamic>(any(),
              body: captureAny(named: 'body')))
          .captured
          .single as Map<String, dynamic>;
      final rows = captured['Строки'] as List;
      expect(rows.length, 2); // только строки 1 и 3
      expect(rows, containsAll(<Map<String, int>>[
        {'НомерСтроки': 1, 'КоличествоФактическое': 5},
        {'НомерСтроки': 3, 'КоличествоФактическое': 2},
      ]));
      expect(rows.any((r) => r['НомерСтроки'] == 2), isFalse);
    });

    test('ничего не отсканировано → пустой массив Строк', () async {
      when(() => client.postJson<dynamic>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      await repo.postDocResult('АЕ-1', {
        1: (qty: 0, action: ''),
        2: (qty: 0, action: ''),
      });

      final captured = verify(() => client.postJson<dynamic>(any(),
              body: captureAny(named: 'body')))
          .captured
          .single as Map<String, dynamic>;
      expect(captured['НомерДокумента'], 'АЕ-1');
      expect(captured['Строки'], isEmpty);
    });

    test('сетевая ошибка Dio → Failure', () async {
      when(() => client.postJson<dynamic>(any(), body: any(named: 'body')))
          .thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      ));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.postDocResult('АЕ-1', {1: (qty: 1, action: '')});

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });
  });

  group('addNewLine — добавление номенклатуры в документ', () {
    test('тело: НомерДокумента + Номенклатура + Характеристика, путь newStr',
        () async {
      when(() => client.postJson<dynamic>(any(),
              body: any(named: 'body')))
          .thenAnswer((_) async => _okResponse<dynamic>());
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.addNewLine(
          'АЕ-00000002', 'Монитор', '23,5" Samsung №CWGCH4ZR503628');

      expect(res, isA<Success>());
      final captured = verify(() => client.postJson<dynamic>(captureAny(),
              body: captureAny(named: 'body')))
          .captured;
      expect(captured[0], 'hs/inventory/newStr');
      expect(captured[1], {
        'НомерДокумента': 'АЕ-00000002',
        'Номенклатура': 'Монитор',
        'Характеристика': '23,5" Samsung №CWGCH4ZR503628',
      });
    });

    test('сетевая ошибка Dio → Failure', () async {
      when(() => client.postJson<dynamic>(any(), body: any(named: 'body')))
          .thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      ));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.addNewLine('АЕ-00000002', 'Монитор', 'Black');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });
  });

  group('getBarcodeInfo — данные номенклатуры по штрихкоду', () {
    test('путь hs/inventory/barcode/{code}, парсинг Номенклатура+Характеристика',
        () async {
      when(() => client.getJson<dynamic>(any()))
          .thenAnswer((_) async => _jsonResponse<dynamic>({
                'Номенклатура': 'Монитор',
                'Характеристика': '23,5" Samsung №CWGCH4ZR503628',
              }));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getBarcodeInfo('2000000009070');

      expect(res, isA<Success>());
      final info = (res as Success<BarcodeInfo?>).value;
      expect(info, isNotNull);
      expect(info!.nomenclature, 'Монитор');
      expect(info.characteristic, '23,5" Samsung №CWGCH4ZR503628');
      // путь точно по контракту
      verify(() => client.getJson<dynamic>('hs/inventory/barcode/2000000009070'))
          .called(1);
    });

    test('принимает строковый JSON (responseType не всегда Map)', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
          (_) async => _jsonResponse<dynamic>(
              jsonEncode({'Номенклатура': 'Монитор', 'Характеристика': 'Black'})));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getBarcodeInfo('2000000009070');

      expect(res, isA<Success>());
      expect((res as Success<BarcodeInfo?>).value!.nomenclature, 'Монитор');
    });

    test('пустой ответ {} → Success(null) (штрихкод не зарегистрирован в 1С)',
        () async {
      final empty = <String, dynamic>{};
      when(() => client.getJson<dynamic>(any()))
          .thenAnswer((_) async => _jsonResponse<dynamic>(empty));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getBarcodeInfo('9999999999999');

      expect(res, isA<Success>());
      expect((res as Success<BarcodeInfo?>).value, isNull);
    });

    test('пустая Номенклатура → Success(null)', () async {
      when(() => client.getJson<dynamic>(any())).thenAnswer(
          (_) async => _jsonResponse<dynamic>(
              {'Номенклатура': '', 'Характеристика': 'что-то'}));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getBarcodeInfo('123');

      expect(res, isA<Success>());
      expect((res as Success<BarcodeInfo?>).value, isNull);
    });

    test('404 → Failure(NotFoundError)', () async {
      when(() => client.getJson<dynamic>(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
            requestOptions: RequestOptions(path: ''), statusCode: 404),
        type: DioExceptionType.badResponse,
      ));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getBarcodeInfo('123');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NotFoundError>());
    });

    test('сетевая ошибка Dio → Failure(NetworkError)', () async {
      when(() => client.getJson<dynamic>(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
      ));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getBarcodeInfo('123');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<NetworkError>());
    });

    test('невалидная JSON-строка → Failure(ParseError)', () async {
      // Сервер вернул 200, но тело — не JSON (например, HTML-ошибка).
      when(() => client.getJson<dynamic>(any()))
          .thenAnswer((_) async => _jsonResponse<dynamic>('не json {'));
      final repo = InventoryRepository(client: client, db: db);

      final res = await repo.getBarcodeInfo('123');

      expect(res, isA<Failure>());
      expect((res as Failure).error, isA<ParseError>());
    });
  });
}
