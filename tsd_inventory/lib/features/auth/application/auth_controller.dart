import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/secure_credentials_store.dart';

import '../data/auth_repository.dart';

/// Сессия авторизованного пользователя.
class AuthSession {
  const AuthSession({required this.login, required this.password});
  final String login;
  final String password;

  /// Логин = ФИО (решение из дизайна).
  String get fio => login;
}

/// Состояние авторизации: session == null = не авторизован.
class AuthState {
  const AuthState({
    this.session,
    this.rememberLogin = true,
    this.rememberPassword = false,
  });
  final AuthSession? session;
  final bool rememberLogin;
  final bool rememberPassword;
  bool get isAuthenticated => session != null;

  AuthState copyWith({
    AuthSession? session,
    bool? rememberLogin,
    bool? rememberPassword,
  }) =>
      AuthState(
        session: session ?? this.session,
        rememberLogin: rememberLogin ?? this.rememberLogin,
        rememberPassword: rememberPassword ?? this.rememberPassword,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  SecureCredentialsStore get _store => ref.read(secureCredentialsStoreProvider);

  /// Репозиторий всегда строится из *текущего* конфига — чтобы при переключении
  /// базы (ERP ↔ ERP_Local) следующий логин шёл уже на выбранную базу.
  AuthRepository _repo() => AuthRepository(ref.read(appConfigProvider));

  /// Ключ активной базы ('erp' / 'erp_local') — учётные данные хранятся раздельно,
  /// т.к. пароли на ERP и ERP_Local могут отличаться.
  String get _storageKey => ref.read(appConfigProvider).storageKey;

  /// Попытка входа. Возвращает null при успехе, [ApiError] при провале.
  /// UI различает [NetworkError] (→ предложить ERP_Local) от остальных ошибок.
  Future<ApiError?> login(
    String login,
    String password, {
    required bool rememberLogin,
    required bool rememberPassword,
  }) async {
    final res = await _repo().login(login, password);
    switch (res) {
      case Success<String>():
        // Сохраняем под ключ активной базы — пароль другой базы не затираем.
        final key = _storageKey;
        if (rememberLogin) {
          await _store.writeLogin(key, login);
        } else {
          await _store.removeLogin(key);
        }
        if (rememberPassword) {
          await _store.writePassword(key, password);
        } else {
          await _store.removePassword(key);
        }
        state = AuthState(
          session: AuthSession(login: login, password: password),
          rememberLogin: rememberLogin,
          rememberPassword: rememberPassword,
        );
        return null; // успех
      case Failure<String>(:final error):
        return error;
    }
  }

  /// Переключиться на локальную базу ERP_Local (fallback при недоступности ERP).
  void useLocalBase() {
    ref.read(connectionTargetProvider.notifier).state = AppConfig.localUrl;
  }

  Future<void> logout() async {
    await _store.clear();
    // Выбор ERP_Local — только до конца сессии: при выходе возвращаем ERP.
    ref.read(connectionTargetProvider.notifier).state = AppConfig.remoteUrl;
    // Сбрасываем запомненный рабочий хост ERP — новый вход снова начнёт с db-srv14.
    DioClient.resetActiveHost();
    state = const AuthState();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

// --- Провайдеры зависимостей core (общие) ---

/// Выбранная база подключения: ERP (db-srv14, по умолчанию) или ERP_Local
/// (fallback при недоступности ERP). Действует до конца сессии — при выходе
/// сбрасывается на [AppConfig.remoteUrl] в [AuthController.logout].
final connectionTargetProvider =
    StateProvider<String>((ref) => AppConfig.remoteUrl);

/// Конфиг приложения с URL выбранной базы. Все репозитории/экраны получают
/// адрес отсюда — переключение базы меняет URL во всём приложении автоматически.
final appConfigProvider = Provider<AppConfig>((ref) {
  final baseUrl = ref.watch(connectionTargetProvider);
  return AppConfig(baseUrl: baseUrl);
});

final secureCredentialsStoreProvider =
    Provider<SecureCredentialsStore>((ref) => SecureCredentialsStore());
