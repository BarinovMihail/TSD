import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Сохранение логина/пароля в Android Keystore (через flutter_secure_storage).
///
/// Учётные данные хранятся **раздельно по базам**: пароли на ERP и ERP_Local
/// могут отличаться, поэтому ключи суффиксируются идентификатором базы
/// (`[storageKey]` — `'erp'` / `'erp_local'`). При переключении базы
/// подставляются сохранённые именно для неё логин/пароль.
class SecureCredentialsStore {
  SecureCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // Легаси-ключи (до раздельного хранения) — для одноразовой миграции.
  static const _kLegacyLogin = 'login';
  static const _kLegacyPassword = 'password';

  String _loginKey(String storageKey) => 'login_$storageKey';
  String _passwordKey(String storageKey) => 'password_$storageKey';

  Future<String?> readLogin(String storageKey) async {
    final v = await _storage.read(key: _loginKey(storageKey));
    if (v != null) return v;
    // Миграция: если новых ключей нет, но есть легаси — считаем, что это ERP.
    if (storageKey == 'erp') {
      return _storage.read(key: _kLegacyLogin);
    }
    return null;
  }

  Future<void> writeLogin(String storageKey, String login) async {
    await _storage.write(key: _loginKey(storageKey), value: login);
    // Перенесли из легаси — чистим старый ключ, чтобы не дублировать.
    await _storage.delete(key: _kLegacyLogin);
  }

  Future<void> removeLogin(String storageKey) async {
    await _storage.delete(key: _loginKey(storageKey));
  }

  Future<String?> readPassword(String storageKey) async {
    final v = await _storage.read(key: _passwordKey(storageKey));
    if (v != null) return v;
    if (storageKey == 'erp') {
      return _storage.read(key: _kLegacyPassword);
    }
    return null;
  }

  Future<void> writePassword(String storageKey, String password) async {
    await _storage.write(key: _passwordKey(storageKey), value: password);
    await _storage.delete(key: _kLegacyPassword);
  }

  Future<void> removePassword(String storageKey) async {
    await _storage.delete(key: _passwordKey(storageKey));
  }

  /// Полная очистка всех баз (выход / смена пользователя).
  Future<void> clear() async {
    await _storage.deleteAll();
  }
}
