import 'package:dio/dio.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';

/// Проверка учётных данных 1С через Basic Auth.
/// Зонд: лёгкий GET к /fio/{логин} под Basic Auth.
///   200/204 → успех; 401/403 → AuthError; сетевая → NetworkError.
class AuthRepository {
  AuthRepository(this._config);
  final AppConfig _config;

  /// Возвращает Success(login) при успехе или Failure.
  Future<Result<String>> login(String login, String password) async {
    final client = DioClient(
      config: _config,
      credentials: BasicCredentials(login, password),
    );
    try {
      final path = 'hs/inventory/fio/${Uri.encodeComponent(login)}';
      final res = await client.getJson<dynamic>(path);
      if (res.statusCode == 200 || res.statusCode == 204) {
        return Success(login);
      }
      return const Failure(AuthError());
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (_) {
      return const Failure(NetworkError());
    }
  }
}
