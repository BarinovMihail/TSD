import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error.dart';
import '../../../core/presentation/confirm_dialog.dart';
import '../../../core/update/application/update_controller.dart';
import '../../../core/update/presentation/update_dialog.dart';
import '../../../l10n/app_strings.dart';
import '../application/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _rememberLogin = true;
  bool _rememberPassword = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Восстановить сохранённые логин/пароль для активной базы и состояние чекбоксов.
    _restoreSavedCredentials();
    // Проверка обновлений при входе (до авторизации — не требует учётки 1С).
    _checkForUpdates();
  }

  Future<void> _restoreSavedCredentials() async {
    final store = ref.read(secureCredentialsStoreProvider);
    final key = ref.read(appConfigProvider).storageKey;
    final login = await store.readLogin(key);
    final password = await store.readPassword(key);
    if (!mounted) return;
    setState(() {
      if (login != null) _loginCtrl.text = login;
      // «Запомнить логин» включён, если логин сохранён.
      _rememberLogin = login != null;
      if (password != null) {
        _passCtrl.text = password;
        // Пароль сохранён → чекбокс «запомнить пароль» был включён.
        _rememberPassword = true;
      }
    });
  }

  Future<void> _checkForUpdates() async {
    final controller = ref.read(updateControllerProvider);
    controller.addListener(_onUpdateStateChanged);
    await controller.checkAndPrompt();
  }

  void _onUpdateStateChanged() {
    final controller = ref.read(updateControllerProvider);
    if (!mounted) return;
    if (controller.hasUpdate && _updateDialogShown == false) {
      _updateDialogShown = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(controller: controller),
      ).then((_) {
        // Диалог закрыли → слушатель больше не нужен.
        if (mounted) {
          controller.removeListener(_onUpdateStateChanged);
        }
      });
    }
  }

  bool _updateDialogShown = false;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
    // Слушатель обновлений мог остаться, если диалог не был показан.
    ref.read(updateControllerProvider).removeListener(_onUpdateStateChanged);
    super.dispose();
  }

  bool get _isValid =>
      _loginCtrl.text.trim().isNotEmpty && _passCtrl.text.isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await ref.read(authControllerProvider.notifier).login(
          _loginCtrl.text.trim(),
          _passCtrl.text,
          rememberLogin: _rememberLogin,
          rememberPassword: _rememberPassword,
        );
    if (!mounted) return;
    if (err == null) {
      context.go('/docs');
      return;
    }
    // Сетевая ошибка → предложить fallback на локальную базу ERP_Local.
    // Прочие ошибки (401/403, 5xx) — показать текстом, как раньше.
    if (err is NetworkError) {
      setState(() => _loading = false);
      _promptUseLocalBase();
    } else {
      setState(() {
        _error = err.userMessage;
        _loading = false;
      });
    }
  }

  /// Диалог: удалённая база ERP недоступна — подключиться к ERP_Local?
  /// При согласии подставляем сохранённые для ERP_Local логин/пароль
  /// (они могут отличаться от учётки ERP) и повторяем вход.
  void _promptUseLocalBase() {
    ConfirmDialog.show(
      context,
      title: const Text(AppStrings.errRemoteUnreachableTitle),
      content: const Text(AppStrings.errRemoteUnreachableBody),
      primaryLabel: AppStrings.retryRemote,
      onPrimary: () {
        // Остаться на ERP — пользователь поправит сеть/данные и повторит.
      },
      secondaryLabel: AppStrings.useLocalBase,
      onSecondary: () {
        ref.read(authControllerProvider.notifier).useLocalBase();
        _switchedToBaseCredentials().then((_) => _submit());
      },
    );
  }

  /// После переключения базы — подставить сохранённые для неё логин/пароль,
  /// т.к. учётки ERP и ERP_Local могут различаться. Если для новой базы ничего
  /// не сохранено — оставляем введённые поля как есть.
  Future<void> _switchedToBaseCredentials() async {
    final store = ref.read(secureCredentialsStoreProvider);
    final key = ref.read(appConfigProvider).storageKey;
    final login = await store.readLogin(key);
    final password = await store.readPassword(key);
    if (!mounted) return;
    setState(() {
      if (login != null) {
        _loginCtrl.text = login;
        _rememberLogin = true;
      }
      if (password != null) {
        _passCtrl.text = password;
        _rememberPassword = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(AppStrings.loginTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 32),
                TextField(
                  controller: _loginCtrl,
                  decoration:
                      const InputDecoration(labelText: AppStrings.loginField),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.passwordField,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility
                          : Icons.visibility_off),
                      tooltip: AppStrings.showPassword,
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _rememberLogin,
                  onChanged: (v) =>
                      setState(() => _rememberLogin = v ?? true),
                  title: const Text(AppStrings.rememberLogin),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _rememberPassword,
                  onChanged: (v) =>
                      setState(() => _rememberPassword = v ?? false),
                  title: const Text(AppStrings.rememberPassword),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 18)),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: (_isValid && !_loading) ? _submit : null,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text(AppStrings.signIn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
