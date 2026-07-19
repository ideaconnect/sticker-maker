import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/app/app.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/settings/settings_store.dart';
import 'package:sticker_maker/core/widgets/app_logo.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sm_about_');
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1080, 2400);
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
          savedProjectsProvider.overrideWith((ref) => <StickerProject>[]),
          savedPacksProvider.overrideWith((ref) => <StickerPack>[]),
          onboardingSeenProvider.overrideWith((ref) => true),
        ],
        child: const StickerMakerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Home avatar opens the About sheet', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    // Home header + sheet header both show the logo mark.
    expect(find.byType(AppLogo), findsNWidgets(2));
    // Both sheet rows are present (leading icons are unique to the sheet here).
    expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
  });

  testWidgets('About → licenses shows attributions', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.article_outlined)); // licenses row
    await tester.pumpAndSettle();

    expect(find.text('Plus Jakarta Sans'), findsOneWidget);
    expect(find.text('SIL OFL 1.1'), findsWidgets);
    // Link to the full aggregated Flutter license page is offered (below the
    // fold in a lazy list, so scroll it into view first).
    await tester.scrollUntilVisible(
      find.text('View full license texts'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('View full license texts'), findsOneWidget);
  });

  testWidgets('About → privacy shows the hosted policy URL', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.verified_user_outlined)); // privacy row
    await tester.pumpAndSettle();

    expect(find.textContaining('sticker-maker/privacy'), findsOneWidget);
    expect(find.textContaining('collects nothing'), findsOneWidget);
  });
}
