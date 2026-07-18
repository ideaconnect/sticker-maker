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

const _oneFrame = StickerProject(
  id: 'p',
  name: 'a',
  frames: [
    Frame(
      id: 'f0',
      layers: [TextLayer(id: 't', name: 'Hi', text: 'Hi', fontFamily: 'Rubik')],
    ),
  ],
);

const _threeFrames = StickerProject(
  id: 'p',
  name: 'anim',
  frames: [
    Frame(id: 'f0'),
    Frame(id: 'f1'),
    Frame(id: 'f2'),
  ],
);

EditorController _controllerFor(ProviderContainer c) =>
    c.read(editorControllerProvider.notifier);

ProviderContainer _container(StickerProject project) {
  final c = ProviderContainer(
    overrides: [
      editorControllerProvider.overrideWith(() => EditorController(project)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('frame ops', () {
    test('duplicateFrame inserts a clone after the index and selects it', () {
      final c = _container(_oneFrame);
      _controllerFor(c).duplicateFrame(0);

      final p = c.read(editorControllerProvider).project;
      expect(p.frameCount, 2);
      expect(p.currentFrameIndex, 1);
      // Same content, fresh layer ids.
      expect(p.frames[1].layers.length, 1);
      expect(p.frames[1].layers.first.id, isNot('t'));
      expect((p.frames[1].layers.first as TextLayer).text, 'Hi');
    });

    test('addFrame duplicates the current frame and appends it', () {
      final c = _container(_threeFrames);
      _controllerFor(c)
        ..selectFrame(1)
        ..addFrame();

      final p = c.read(editorControllerProvider).project;
      expect(p.frameCount, 4);
      expect(p.currentFrameIndex, 3);
    });

    test('deleteFrame removes a frame but keeps at least one', () {
      final c = _container(_threeFrames);
      final ctrl = _controllerFor(c);
      ctrl.deleteFrame(0);
      expect(c.read(editorControllerProvider).project.frameCount, 2);

      ctrl
        ..deleteFrame(0)
        ..deleteFrame(0); // second call is a no-op at one frame
      expect(c.read(editorControllerProvider).project.frameCount, 1);
    });

    test('frame add/duplicate/delete are undoable', () {
      final c = _container(_threeFrames);
      final ctrl = _controllerFor(c);
      ctrl.duplicateFrame(0);
      expect(c.read(editorControllerProvider).project.frameCount, 4);
      ctrl.undo();
      expect(c.read(editorControllerProvider).project.frameCount, 3);
    });

    test(
      'deleteFrame keeps you on the same frame when an earlier one goes',
      () {
        const p = StickerProject(
          id: 'p',
          name: 'a',
          frames: [
            Frame(
              id: 'f0',
              layers: [
                TextLayer(id: 'a', name: 'A', text: 'A', fontFamily: 'Rubik'),
              ],
            ),
            Frame(
              id: 'f1',
              layers: [
                TextLayer(id: 'b', name: 'B', text: 'B', fontFamily: 'Rubik'),
              ],
            ),
            Frame(
              id: 'f2',
              layers: [
                TextLayer(id: 'c', name: 'C', text: 'C', fontFamily: 'Rubik'),
              ],
            ),
          ],
        );
        final c = _container(p);
        _controllerFor(c)
          ..selectFrame(1) // viewing B
          ..deleteFrame(0); // remove A

        final proj = c.read(editorControllerProvider).project;
        expect(proj.frameCount, 2);
        expect(proj.currentFrameIndex, 0);
        expect((proj.currentFrame.layers.first as TextLayer).text, 'B');
      },
    );

    test('a new layer lands only on the current frame by default', () {
      final c = _container(_threeFrames);
      _controllerFor(c)
        ..selectFrame(1)
        ..addTextLayer(text: 'only');

      final p = c.read(editorControllerProvider).project;
      expect(p.frames[0].layers, isEmpty);
      expect(p.frames[1].layers.map((l) => (l as TextLayer).text), ['only']);
      expect(p.frames[2].layers, isEmpty);
    });

    test('addToAllFrames adds a fresh-id copy to every frame', () {
      final c = _container(_threeFrames);
      _controllerFor(c)
        ..addToAllFrames = true
        ..addTextLayer(text: 'wiggle');

      final p = c.read(editorControllerProvider).project;
      for (final f in p.frames) {
        expect(f.layers.map((l) => (l as TextLayer).text), ['wiggle']);
      }
      final ids = p.frames.map((f) => f.layers.first.id).toSet();
      expect(ids.length, 3, reason: 'unique layer id per frame');
    });
  });

  group('playback', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('sm_frames_');
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.physicalSize = const Size(824, 1784);
      view.devicePixelRatio = 2.0;
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('Play loops the frames and the counter tracks them', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectRepositoryProvider.overrideWithValue(
              ProjectRepository(baseDir: tmp),
            ),
            editorControllerProvider.overrideWith(
              () => EditorController(_threeFrames),
            ),
          ],
          child: MaterialApp(
            theme: buildStickerTheme(),
            home: const EditorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Frames'));
      await tester.pumpAndSettle();
      expect(find.text('Frame 1 / 3'), findsOneWidget);
      // Animated-project affordances (#36 apply-to-all, #37 onion skin).
      expect(find.text('New layers to all frames'), findsOneWidget);
      expect(find.text('Onion skin (ghost previous)'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pump(); // start the timer

      // Default 8 fps → ~125ms/frame.
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.text('Frame 2 / 3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.text('Frame 3 / 3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.text('Frame 1 / 3'), findsOneWidget, reason: 'loops');

      // Pause halts advancement.
      await tester.tap(find.text('Pause'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Frame 1 / 3'), findsOneWidget);

      // Let the debounced auto-save timer fire so none is pending at teardown.
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
