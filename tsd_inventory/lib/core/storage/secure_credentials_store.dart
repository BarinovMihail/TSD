import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Сохранение логина/пароля в Android Keystore (через flutter_secure_storage).
class SecureCredentialsStore {
  SecureCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kLogin = 'login';
  static const _kPassword = 'password';

  Future<String?> readLogin() => _storage.read(key: _kLogin);
  Future<void> writeLogin(String login) =>
      _storage.write(key: _kLogin, value: login);
  Future<void> removeLogin() => _storage.delete(key: _kLogin);

  Future<String?> readPassword() => _storage.read(key: _kPassword);
  Future<void> writePassword(String password) =>
      _storage.write(key: _kPassword, value: password);
  Future<void> removePassword() => _storage.delete(key: _kPassword);

  /// Полная очистка (выход / смена пользователя).
  Future<void> clear() async {
    await _storage.deleteAll();
  }
}
