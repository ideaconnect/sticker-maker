import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/settings/settings_store.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import 'router.dart';

/// Root shell. Resolves the first-run flag, then hosts a [MaterialApp.router]
/// starting on onboarding (first run) or Home. Shows a themed splash while the
/// flag loads; fails open to Home if it can't be read.
class StickerMakerApp extends ConsumerWidget {
  const StickerMakerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(onboardingSeenProvider);
    final start = seen.maybeWhen(
      data: (v) => v ? '/' : '/onboarding',
      error: (_, _) => '/', // fail open — never trap the user on a splash
      orElse: () => null,
    );
    if (start == null) return const _Splash();
    return _RouterHost(initialLocation: start);
  }
}

/// Owns the per-instance [GoRouter] so navigation state never leaks between
/// tests and the router is disposed with the app.
class _RouterHost extends StatefulWidget {
  const _RouterHost({required this.initialLocation});

  final String initialLocation;

  @override
  State<_RouterHost> createState() => _RouterHostState();
}

class _RouterHostState extends State<_RouterHost> {
  late final GoRouter _router = createAppRouter(
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sticker Maker',
      debugShowCheckedModeBanner: false,
      theme: buildStickerTheme(),
      routerConfig: _router,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildStickerTheme(),
      home: const Scaffold(
        backgroundColor: AppColors.pageBackground,
        body: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}
