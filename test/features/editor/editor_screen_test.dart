import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/editor_screen.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';

Future<void> pumpEditor(WidgetTester tester, {StickerProject? project}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: project == null
          ? const []
          : [
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
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(824, 1784);
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
}
