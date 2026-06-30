import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme/app_theme.dart';

/// Корневой виджет. Router расширяется в Task 14.
class TsdApp extends ConsumerWidget {
  const TsdApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Инвентаризация',
      theme: appTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Временный провайдер роутера (расширяется в Task 14).
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('login (Task 14)')),
        ),
      ),
    ],
  );
});
