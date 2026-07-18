import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/editor_screen.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/home/project_repository.dart';

late Directory _tmp;

Future<void> pumpEditor(WidgetTester tester, StickerProject project) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectRepositoryProvider.overrideWithValue(
          ProjectRepository(baseDir: _tmp),
        ),
        editorControllerProvider.overrideWith(() => EditorController(project)),
      ],
      child: MaterialApp(
        theme: buildStickerTheme(),
        home: const EditorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _bubbleProject = StickerProject(
  id: 'p',
  name: 'b',
  frames: [
    Frame(
      id: 'f',
      layers: [BubbleLayer(id: 'b1', name: 'Woof!')],
    ),
  ],
);

const _emptyProject = StickerProject(
  id: 'e',
  name: 'e',
  frames: [Frame(id: 'f')],
);

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('sm_bubble_');
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(824, 1784);
    view.devicePixelRatio = 2.0;
  });
  tearDown(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  group('BubbleLayer model', () {
    test('round-trips through JSON', () {
      const bubble = BubbleLayer(
        id: 'b',
        name: 'Hi',
        text: 'Hi!',
        shape: BubbleShape.thought,
        fontFamily: 'Rubik',
        fontSize: 30,
        fillColor: Color(0xFF00FF00),
        strokeColor: Color(0xFF0000FF),
        textColor: Color(0xFFFF0000),
        tail: Offset(0.4, 1.1),
      );
      final restored = Layer.fromJson(bubble.toJson());
      expect(restored, equals(bubble));
      expect(restored, isA<BubbleLayer>());
    });

    test('unknown shape falls back to speech', () {
      final json = const BubbleLayer(id: 'b', name: 'x').toJson()
        ..['shape'] = 'nonsense';
      final restored = Layer.fromJson(json) as BubbleLayer;
      expect(restored.shape, BubbleShape.speech);
    });
  });

  testWidgets('Add bubble drops a bubble layer with the default caption', (
    tester,
  ) async {
    await pumpEditor(tester, _emptyProject);

    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add bubble'));
    await tester.pumpAndSettle();

    // Adding jumps straight into the bubble editor with the default caption.
    expect(find.text('Comic bubble'), findsOneWidget);
    expect(find.text('Woof!'), findsWidgets); // on the canvas (+ panel field)
  });

  testWidgets('selecting a bubble shows the bubble panel, not the text panel', (
    tester,
  ) async {
    await pumpEditor(tester, _bubbleProject);

    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bubble layer')); // select via the row subtitle
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text')); // the Text tool hosts bubble editing
    await tester.pumpAndSettle();

    // Bubble panel, with the three shape presets.
    expect(find.text('Comic bubble'), findsOneWidget);
    expect(find.text('Speech'), findsOneWidget);
    expect(find.text('Thought'), findsOneWidget);
    expect(find.text('Shout'), findsOneWidget);
    // Not the text-layer panel.
    expect(find.text('Tap a font to preview'), findsNothing);
  });
}
