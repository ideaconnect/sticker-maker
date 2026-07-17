import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import 'router.dart';

/// Root widget: wires the dark theme and a per-instance [GoRouter] into a
/// [MaterialApp.router].
class StickerMakerApp extends StatefulWidget {
  const StickerMakerApp({super.key});

  @override
  State<StickerMakerApp> createState() => _StickerMakerAppState();
}

class _StickerMakerAppState extends State<StickerMakerApp> {
  late final GoRouter _router = createAppRouter();

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
