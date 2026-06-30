import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
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

  late final _repo = AuthRepository(ref.watch(appConfigProvider));
  late final _store = ref.watch(secureCredentialsStoreProvider);

  /// Попытка входа. Возвращает null при успехе, сообщение об ошибке при провале.
  Future<String?> login(
    String login,
    String password, {
    required bool rememberLogin,
    required bool rememberPassword,
  }) async {
    final res = await _repo.login(login, password);
    return res.maybeWhen(
      onValue: (_) async {
        if (rememberLogin) {
          await _store.writeLogin(login);
        } else {
          await _store.removeLogin();
        }
        if (rememberPassword) {
          await _store.writePassword(password);
        } else {
          await _store.removePassword();
        }
        state = AuthState(
          session: AuthSession(login: login, password: password),
          rememberLogin: rememberLogin,
          rememberPassword: rememberPassword,
        );
        return null; // успех
      },
      orElse: (err) => err.userMessage,
    );
  }

  Future<void> logout() async {
    await _store.clear();
    state = const AuthState();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

// --- Провайдеры зависимостей core (общие, определим здесь при первом использовании) ---
final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig());
final secureCredentialsStoreProvider =
    Provider<SecureCredentialsStore>((ref) => SecureCredentialsStore());
