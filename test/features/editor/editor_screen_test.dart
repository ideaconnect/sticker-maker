import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/editor_screen.dart';
import 'package:sticker_maker/features/editor/services/image_import.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/home/project_repository.dart';

late Directory _tempDir;

/// Hands out predetermined asset paths instead of opening a real picker.
class _FakeImport extends ImageImportService {
  _FakeImport(this.paths);

  final List<String> paths;
  int _next = 0;

  @override
  Future<String?> pickFromGallery() async => paths[_next++ % paths.length];
}

Future<void> pumpEditor(
  WidgetTester tester, {
  StickerProject? project,
  ImageImportService? importService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          ProjectRepository(baseDir: _tempDir),
        ),
        if (importService != null)
          imageImportServiceProvider.overrideWithValue(importService),
        if (project != null)
          editorControllerProvider.overrideWith(
            () => EditorController(project),
          ),
      ],
      child: MaterialApp(
        theme: buildStickerTheme(),
        home: const EditorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

StickerProject oneTextProject() => const StickerProject(
  id: 'p',
  name: 'Test',
  frames: [
    Frame(
      id: 'f',
      layers: [
        TextLayer(id: 't', name: 'Caption', text: 'Hi', fontFamily: 'Rubik'),
      ],
    ),
  ],
);

void main() {
  setUp(() {
    _tempDir = Directory.systemTemp.createTempSync('sm_editor_');
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(824, 1784);
    view.devicePixelRatio = 2.0;
  });
  tearDown(() {
    imageCache.clear();
    imageCache.clearLiveImages();
    try {
      if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows can briefly keep decoded-file handles open.
    }
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('Layers tool lists real layers and Add appends one', (
    tester,
  ) async {
    await pumpEditor(tester, project: oneTextProject());

    await tester.tap(find.text('Layers')); // tool tab
    await tester.pumpAndSettle();

    expect(find.text('Caption'), findsOneWidget);
    expect(find.text('Text layer'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add text')); // choose from the Add menu
    await tester.pumpAndSettle();

    expect(find.text('Text layer'), findsNWidgets(2));
  });

  testWidgets('selecting a layer then Text tool edits it', (tester) async {
    await pumpEditor(tester, project: oneTextProject());

    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caption')); // select the layer
    await tester.pumpAndSettle();

    await tester.tap(find.text('Text')); // Text tool tab
    await tester.pumpAndSettle();

    // The Text panel is showing, bound to the selected caption.
    expect(find.widgetWithText(TextField, 'Hi'), findsOneWidget);
    expect(find.text('Tap a font to preview'), findsOneWidget);
  });

  testWidgets('long-pressing a layer renames it', (tester) async {
    await pumpEditor(tester, project: oneTextProject());
    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Caption'));
    await tester.pumpAndSettle();

    // Rename dialog is up; replace the text and confirm.
    await tester.enterText(find.byType(TextField).last, 'Speech');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Speech'), findsOneWidget);
    expect(find.text('Caption'), findsNothing);
  });

  testWidgets('undo button enables after an edit and reverses it', (
    tester,
  ) async {
    await pumpEditor(tester, project: oneTextProject());

    // Undo starts disabled.
    final undoButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.undo),
        matching: find.byType(IconButton),
      ),
    );
    expect(undoButton.onPressed, isNull);

    // Make an edit: add a text layer via the Layers panel.
    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    expect(find.text('Text layer'), findsNWidgets(2));

    // Undo is now enabled; tapping it reverses the add.
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.text('Text layer'), findsOneWidget);
  });

  testWidgets('switching to Frames shows the frames panel', (tester) async {
    await pumpEditor(tester); // demo project

    await tester.tap(find.text('Frames'));
    await tester.pumpAndSettle();

    expect(find.text('Animation frames'), findsOneWidget);
  });

  testWidgets('undo resyncs the caption field to the reverted text', (
    tester,
  ) async {
    await pumpEditor(tester, project: oneTextProject());

    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caption')); // select the layer
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text')); // Text tool
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Hi'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Hiya');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();

    // Reselect the layer (its name reverted to 'Caption') and reopen Text.
    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caption'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();

    // The field reflects the reverted model text, not the stale 'Hiya'.
    expect(find.widgetWithText(TextField, 'Hi'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Hiya'), findsNothing);
  });

  testWidgets('empty project shows the drop-photo placeholder', (tester) async {
    await pumpEditor(
      tester,
      project: const StickerProject(
        id: 'e',
        name: 'Empty',
        frames: [Frame(id: 'f')],
      ),
    );
    expect(find.text('Drop your pet photo'), findsOneWidget);
  });

  testWidgets(
    'photos add from the Adjust tool, auto-number, and delete cleanly (#77)',
    (tester) async {
      // Real files, so the canvas renders images (not name placeholders).
      final paths = ['${_tempDir.path}/one.png', '${_tempDir.path}/two.png'];
      for (final p in paths) {
        File(p).writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
      }
      await pumpEditor(
        tester,
        project: const StickerProject(
          id: 'multi',
          name: 'Multi',
          frames: [Frame(id: 'f')],
        ),
        importService: _FakeImport(paths),
      );

      // The default Adjust panel offers Add directly — no Layers detour.
      expect(find.text('Adjust'), findsWidgets);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();

      // Import lands on Adjust with the photo selected (Reset chip bound).
      expect(find.text('Reset'), findsOneWidget);

      // Second photo via the same chip; then inspect the Layers panel.
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Layers'));
      await tester.pumpAndSettle();
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Photo 2'), findsOneWidget);

      // Selecting a specific photo row selects that layer.
      await tester.tap(find.text('Photo 2'));
      await tester.pumpAndSettle();

      // Deleting "Photo 2" leaves "Photo" (and its own row) intact.
      final photo2Row = find
          .ancestor(of: find.text('Photo 2'), matching: find.byType(InkWell))
          .first;
      await tester.tap(
        find.descendant(
          of: photo2Row,
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Photo 2'), findsNothing);
      expect(find.text('Photo'), findsOneWidget);
    },
  );
}
