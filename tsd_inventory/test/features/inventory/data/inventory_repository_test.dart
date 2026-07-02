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
Response<T> _okResponse<T>() => Response<T>(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
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
}
