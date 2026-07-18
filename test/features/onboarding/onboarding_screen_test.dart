import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sticker_maker/app/app.dart';
import 'package:sticker_maker/core/settings/settings_store.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/onboarding/onboarding_screen.dart';

/// In-memory settings so navigation completes under widget-test fake-async
/// (real file IO would not).
class _FakeSettingsStore extends SettingsStore {
  bool seen = false;

  @override
  Future<bool> onboardingSeen() async => seen;

  @override
  Future<void> setOnboardingSeen(bool value) async => seen = value;
}

Future<_FakeSettingsStore> _pumpOnboarding(WidgetTester tester) async {
  final store = _FakeSettingsStore();
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('HOME STUB'))),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(
        theme: buildStickerTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 2.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('opens on the first page with Skip and Next', (tester) async {
    await _pumpOnboarding(tester);

    expect(find.text('Make it yours'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('advancing to the last page shows the no-upsell promise', (
    tester,
  ) async {
    await _pumpOnboarding(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.textContaining('no upsells'), findsOneWidget);
  });

  testWidgets('Skip records the flag and routes Home', (tester) async {
    final store = await _pumpOnboarding(tester);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(store.seen, isTrue);
    expect(find.text('HOME STUB'), findsOneWidget);
  });

  testWidgets('Get started records the flag and routes Home', (tester) async {
    final store = await _pumpOnboarding(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(store.seen, isTrue);
    expect(find.text('HOME STUB'), findsOneWidget);
  });

  testWidgets('the app shell shows onboarding on first run', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(_FakeSettingsStore()),
          onboardingSeenProvider.overrideWith((ref) => false),
        ],
        child: const StickerMakerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Make it yours'), findsOneWidget);
  });
}
