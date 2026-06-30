import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/application/auth_controller.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/docs/presentation/docs_list_screen.dart';
import 'features/inventory/presentation/inventory_screen.dart';
import 'theme/app_theme.dart';

class TsdApp extends ConsumerWidget {
  const TsdApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Инвентаризация',
      theme: appTheme(),
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final authed = ref.read(authControllerProvider).isAuthenticated;
      final onLogin = state.matchedLocation == '/login';
      if (!authed && !onLogin) return '/login';
      if (authed && onLogin) return '/docs';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/docs',
        builder: (context, state) => const DocsListScreen(),
      ),
      GoRoute(
        path: '/docs/:code',
        builder: (context, state) =>
            InventoryScreen(docCode: state.pathParameters['code']!),
      ),
    ],
  );
});
