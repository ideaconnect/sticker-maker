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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sticker_maker/app/app.dart';

/// Wipes the on-device projects directory so each test starts from a known
/// empty state (no leftover stickers from a previous run or test).
Future<void> _resetProjects() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/projects');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
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

  setUp(_resetProjects);

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
}
