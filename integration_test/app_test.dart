// End-to-end tests that drive the *real* app on a device/emulator, the way a
// user would: launching from `main`'s widget tree, navigating the real router
// back stack, and hitting real on-device file IO for persistence.
//
// These complement the unit/widget tests (which mock file IO and pump screens
// in isolation). Run with:
//   flutter test integration_test/app_test.dart -d <emulator-id>
//
// The "Playwright-like" part: each test launches the app, taps through a user
// journey, and asserts on what's actually on screen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sticker_maker/app/app.dart';

/// Wipes an on-device data directory (`projects`, `packs`, …) under app docs so
/// each test starts from a known empty state.
Future<void> _wipeDir(String name) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}

/// Seeds the first-run flag (#55). Journey tests want to start past onboarding,
/// on Home; the onboarding test flips this to false to see the intro.
Future<void> _setOnboardingSeen(bool seen) async {
  final base = await getApplicationDocumentsDirectory();
  await File(
    '${base.path}/settings.json',
  ).writeAsString(jsonEncode({'onboardingSeen': seen}));
}

/// Launches the full app exactly as `main()` does (real providers, real
/// router) and waits for the first frame to settle.
Future<void> launchApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: StickerMakerApp()));
  await tester.pumpAndSettle();
}

/// Opens a fresh sticker from Home and lands on the editor.
Future<void> openNewSticker(WidgetTester tester) async {
  await tester.tap(find.text('New Sticker'));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await _wipeDir('projects');
    await _wipeDir('packs');
    await _setOnboardingSeen(
      true,
    ); // journey tests start on Home, not the intro
  });

  testWidgets('app boots to Home with brand, hero action and empty state', (
    tester,
  ) async {
    await launchApp(tester);

    expect(find.text('Sticker Maker'), findsOneWidget);
    expect(find.text('New Sticker'), findsOneWidget);
    expect(find.text('Recent stickers'), findsOneWidget);
    // No projects on disk (we wiped them) → the empty state shows.
    expect(find.text('No stickers yet'), findsOneWidget);
  });

  testWidgets('New Sticker opens the editor on an empty transparent canvas', (
    tester,
  ) async {
    await launchApp(tester);
    await openNewSticker(tester);

    expect(find.text('512 × 512 · transparent'), findsOneWidget);
    expect(find.text('Cut out'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    // Empty project prompts the user to drop a photo.
    expect(find.text('Drop your pet photo'), findsOneWidget);
  });

  testWidgets('add a text layer, then undo and redo it', (tester) async {
    await launchApp(tester);
    await openNewSticker(tester);

    // Open the Layers tool; a fresh sticker has no layers yet.
    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    expect(find.text('Text layer'), findsNothing);

    // Add → Add text.
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    expect(find.text('Text layer'), findsOneWidget);

    // Undo reverses the add; redo re-applies it.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.text('Text layer'), findsNothing);

    await tester.tap(find.byIcon(Icons.redo));
    await tester.pumpAndSettle();
    expect(find.text('Text layer'), findsOneWidget);
  });

  testWidgets('Text tool adds a caption and edits it live on the canvas', (
    tester,
  ) async {
    await launchApp(tester);
    await openNewSticker(tester);

    // Open the Text tool on an empty sticker. 'Text' is unambiguous here
    // because no text layer exists yet whose name/content could collide with
    // the tab label.
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();

    // The panel offers to add a caption; adding one drops a 'Woof!' layer and
    // selects it, so the caption field and canvas both show it.
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    expect(find.text('Woof!'), findsWidgets); // rendered on the canvas

    // Editing the caption field updates the sticker live.
    await tester.enterText(find.byType(TextField).first, 'Meow!');
    await tester.pumpAndSettle();
    expect(find.text('Meow!'), findsWidgets);
    expect(find.text('Woof!'), findsNothing);
  });

  testWidgets('Frames tool reveals the animation panel', (tester) async {
    await launchApp(tester);
    await openNewSticker(tester);

    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();

    expect(find.text('Animation frames'), findsOneWidget);
  });

  testWidgets('Export button navigates to the export screen', (tester) async {
    await launchApp(tester);
    await openNewSticker(tester);

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export sticker'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets('back button pops the real router stack to Home', (tester) async {
    await launchApp(tester);
    await openNewSticker(tester);
    expect(find.text('512 × 512 · transparent'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(find.text('New Sticker'), findsOneWidget);
    expect(find.text('512 × 512 · transparent'), findsNothing);
  });

  testWidgets('a new sticker persists to disk and shows in Recent', (
    tester,
  ) async {
    await launchApp(tester);
    expect(find.text('No stickers yet'), findsOneWidget);

    await openNewSticker(tester);
    // Give the immediate save + any debounced auto-save time to hit disk.
    await Future<void>.delayed(const Duration(seconds: 1));

    // Back to Home; the real savedProjectsProvider re-reads from disk.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    // The freshly created sticker is now listed (empty state gone).
    expect(find.text('No stickers yet'), findsNothing);
    expect(find.text('Untitled'), findsWidgets);
  });

  testWidgets('Templates quickstart applies a template into the editor', (
    tester,
  ) async {
    await launchApp(tester);

    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a look — add your photo after.'), findsOneWidget);

    await tester.tap(find.text('Woof!')); // card label; preview renders WOOF!
    await tester.pumpAndSettle();

    expect(find.text('512 × 512 · transparent'), findsOneWidget);
    expect(find.text('WOOF!'), findsWidgets);
  });

  testWidgets('a comic bubble can be added from the editor', (tester) async {
    await launchApp(tester);
    await openNewSticker(tester);

    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bubble'));
    await tester.pumpAndSettle();

    // Jumped into the bubble editor with the default caption on the canvas.
    expect(find.text('Comic bubble'), findsOneWidget);
    expect(find.text('Woof!'), findsWidgets);
  });

  testWidgets('Frames: adding a frame makes the project animated', (
    tester,
  ) async {
    await launchApp(tester);
    await openNewSticker(tester);

    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();
    expect(find.text('Animation frames'), findsOneWidget);

    // Add a second frame via the strip's + button → project is now animated,
    // so the on-canvas frame counter appears.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.textContaining('/ 2'), findsWidgets);
  });

  testWidgets('first run shows onboarding; Skip lands on Home (#55)', (
    tester,
  ) async {
    await _setOnboardingSeen(false); // undo setUp's seed for this test
    await launchApp(tester);

    expect(find.text('Make it yours'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('New Sticker'), findsOneWidget);
  });

  testWidgets('Home opens the pack manager and creates a pack (#45)', (
    tester,
  ) async {
    await launchApp(tester);
    await tester.tap(find.text('Sticker packs'));
    await tester.pumpAndSettle();
    expect(find.text('No packs yet'), findsOneWidget);

    await tester.tap(find.text('New pack'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My Pack');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Landed in the pack detail editor.
    expect(find.text('My Pack'), findsWidgets);
    expect(find.text('Add stickers'), findsOneWidget);
  });

  testWidgets('Home "See all" opens the searchable list (#63)', (tester) async {
    await launchApp(tester);
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();

    expect(find.text('All stickers'), findsOneWidget);
    // 'No stickers yet' also shows on Home (still mounted under this route), so
    // assert on the search hint, which is unique to this screen.
    expect(find.text('Search your stickers'), findsOneWidget);
  });

  testWidgets('an emoji can be dropped onto the canvas (#61)', (tester) async {
    await launchApp(tester);
    await openNewSticker(tester);

    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add emoji'));
    await tester.pumpAndSettle();
    expect(find.text('Add a sticker'), findsOneWidget); // the emoji picker

    await tester.tap(find.text('😀'));
    await tester.pumpAndSettle();

    // Dropped as a layer and rendered on the canvas (real emoji font on device).
    expect(find.text('😀'), findsWidgets);
  });

  testWidgets('About sheet reaches the open-source licenses (#53)', (
    tester,
  ) async {
    await launchApp(tester);
    await tester.tap(
      find.byIcon(Icons.more_horiz),
    ); // Home avatar → About sheet
    await tester.pumpAndSettle();
    // Tap the licenses row by its icon (label uses a non-breaking hyphen).
    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Plus Jakarta Sans'), findsOneWidget);
  });
}
