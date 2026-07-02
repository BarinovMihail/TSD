import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    // Восстановить сохранённые логин/пароль и состояние чекбоксов (если были).
    Future(() async {
      final store = ref.read(secureCredentialsStoreProvider);
      final login = await store.readLogin();
      final password = await store.readPassword();
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
    });
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
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
    } else {
      setState(() {
        _error = err;
        _loading = false;
      });
    }
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
