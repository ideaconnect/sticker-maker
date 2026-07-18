import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/app/app.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/settings/settings_store.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sm_test_');
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(824, 1784);
    view.devicePixelRatio = 2.0;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          projectRepositoryProvider.overrideWithValue(
            ProjectRepository(baseDir: tempDir),
          ),
          packRepositoryProvider.overrideWithValue(
            PackRepository(baseDir: tempDir),
          ),
          // Resolve immediately so pumpAndSettle doesn't hang on real file IO.
          savedProjectsProvider.overrideWith((ref) => <StickerProject>[]),
          savedPacksProvider.overrideWith((ref) => <StickerPack>[]),
          // These tests exercise the app past first-run onboarding.
          onboardingSeenProvider.overrideWith((ref) => true),
        ],
        child: const StickerMakerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home screen renders brand and primary action', (tester) async {
    await pumpApp(tester);

    expect(find.text('Sticker Maker'), findsOneWidget);
    expect(find.text('New Sticker'), findsOneWidget);
    expect(find.text('Recent stickers'), findsOneWidget);
  });

  testWidgets('New Sticker navigates to the editor', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('New Sticker'));
    await tester.pumpAndSettle();

    expect(find.text('512 × 512 · transparent'), findsOneWidget);
    expect(find.text('Cut out'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('Editor Export button navigates to the export screen', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('New Sticker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export sticker'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets('Home "Sticker packs" opens the packs manager', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Sticker packs'));
    await tester.pumpAndSettle();

    // PacksScreen empty state (unique to that screen).
    expect(find.text('No packs yet'), findsOneWidget);
    expect(find.text('New pack'), findsOneWidget);
  });

  testWidgets('Editor back button pops to Home (real back stack)', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('New Sticker'));
    await tester.pumpAndSettle();
    // Editor-only subtitle confirms we're on the editor.
    expect(find.text('512 × 512 · transparent'), findsOneWidget);

    // The chevron back must pop (not replace) so Android system back works too.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(find.text('New Sticker'), findsOneWidget);
    expect(find.text('512 × 512 · transparent'), findsNothing);
  });
}
