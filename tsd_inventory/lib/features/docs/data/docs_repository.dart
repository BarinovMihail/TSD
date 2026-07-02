import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';

import '../domain/doc_list_item.dart';
import '../domain/doc_list_parser.dart';

final _log = Logger('DocsRepository');

/// Загрузка списка документов инвентаризации по ФИО.
/// GET /hs/inventory/fio/{ФИО} (ФИО URL-encoded).
class DocsRepository {
  DocsRepository(this._client);
  final DioClient _client;

  Future<Result<List<DocListItem>>> getByFio(String fio) async {
    final path = 'hs/inventory/fio/${Uri.encodeComponent(fio)}';
    _log.info('GET $path (fio="$fio")');
    try {
      final res = await _client.getJson<dynamic>(path);
      final data = res.data;
      _log.info('HTTP ${res.statusCode} | data runtimeType=${data.runtimeType}');
      _log.fine('Необработанный ответ: $data');
      // Данные могут прийти строкой (если contentType не json) — страхуемся.
      final parsed = data is String ? jsonDecode(data) : data;
      final list = parseDocList(parsed);
      _log.info('Распознано документов: ${list.length}');
      return Success(list);
    } on DioException catch (e) {
      _log.warning('DioException: type=${e.type} status=${e.response?.statusCode} '
          'body=${e.response?.data}');
      return Failure(ApiError.fromDio(e));
    } catch (e, st) {
      _log.warning('Неожиданная ошибка разбора: $e\n$st');
      return const Failure(ParseError('Не удалось разобрать список документов'));
    }
  }
}
