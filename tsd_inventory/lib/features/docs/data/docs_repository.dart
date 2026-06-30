import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';

import '../domain/doc_list_item.dart';
import '../domain/doc_list_parser.dart';

/// Загрузка списка документов инвентаризации по ФИО.
/// GET /hs/inventory/fio/{ФИО} (ФИО URL-encoded).
class DocsRepository {
  DocsRepository(this._client);
  final DioClient _client;

  Future<Result<List<DocListItem>>> getByFio(String fio) async {
    final path = 'hs/inventory/fio/${Uri.encodeComponent(fio)}';
    try {
      final res = await _client.getJson<dynamic>(path);
      final data = res.data;
      // Данные могут прийти строкой (если contentType не json) — страхуемся.
      final parsed = data is String ? jsonDecode(data) : data;
      return Success(parseDocList(parsed));
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      return const Failure(ParseError('Не удалось разобрать список документов'));
    }
  }
}
