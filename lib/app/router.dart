import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../features/editor/editor_screen.dart';
import '../features/export/export_screen.dart';
import '../features/gallery/gallery_screen.dart';
import '../features/home/home_screen.dart';

/// App route names, referenced by widgets via `context.goNamed(...)` /
/// `context.pushNamed(...)`.
abstract final class Routes {
  Routes._();
  static const home = 'home';
  static const editor = 'editor';
  static const export = 'export';
  static const gallery = 'gallery';
}

/// Builds the app's [GoRouter]. Home → Editor → Export is a push-style
/// drill-down so the Android back button pops correctly. Created per app
/// instance (see `StickerMakerApp`) so navigation state never leaks between
/// tests.
GoRouter createAppRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: Routes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/editor',
      name: Routes.editor,
      builder: (context, state) => const EditorScreen(),
    ),
    GoRoute(
      path: '/export',
      name: Routes.export,
      builder: (context, state) => const ExportScreen(),
    ),
    // Developer-only design-system gallery: never registered in release builds.
    if (kDebugMode)
      GoRoute(
        path: '/gallery',
        name: Routes.gallery,
        builder: (context, state) => const GalleryScreen(),
      ),
  ],
);
