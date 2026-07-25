import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// App-wide router. Auth-aware redirect logic (mirroring webapp's
/// `authGuard` in src/router/index.ts) is added once the auth store exists.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const _PlaceholderHomeScreen(),
      ),
      // TODO(auth): '/login' route
      // TODO(auth): redirect: unauthenticated -> /login, authenticated -> /
    ],
  );
});

class _PlaceholderHomeScreen extends StatelessWidget {
  const _PlaceholderHomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LwkApply')),
      body: const Center(child: Text('Scaffold OK — auth screen next')),
    );
  }
}
