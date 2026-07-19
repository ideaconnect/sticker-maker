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
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/editor/state/editor_tool.dart';
import 'package:sticker_maker/features/editor/widgets/editor_canvas.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';

/// End-to-end proof that the editor wires delete-on-supersede correctly
/// (#review perf 2026-07-19): erasing writes a fresh mask PNG per stroke, and
/// the file a stroke replaces is reclaimed once it falls out of undo reach —
/// never while a live undo entry could still restore it.
///
/// The assertions are on the GC *decision* (which mask the editor asks to
/// delete, and when), recorded via [_RecordingMaskStore]. The physical
/// `File.delete` is exercised deterministically by SupersededMaskCollector in
/// mask_store_test.dart; here it would be Windows-file-lock-flaky (a just-decoded
/// mask PNG can keep a handle), so we don't assert on the file vanishing.
late Directory _tmp;

class _RecordingMaskStore extends MaskStore {
  _RecordingMaskStore({super.baseDir});

  final List<String> deleteRequests = [];

  @override
  Future<void> deleteMask(String path) async {
    deleteRequests.add(path);
    await super.deleteMask(path);
  }
}

String? _maskPathOf(ProviderContainer container) {
  final layer = container
      .read(editorControllerProvider)
      .currentFrame
      .layers
      .whereType<ImageLayer>()
      .first;
  return layer.maskPath;
}

/// Drives one erase stroke over the canvas and pumps (interleaving real async
/// for the stroke's file IO) until the layer's mask path advances past
/// [previous]. Returns the new path.
Future<String> _eraseStroke(
  WidgetTester tester,
  ProviderContainer container, {
  String? previous,
}) async {
  await tester.drag(find.byType(EditorCanvas), const Offset(28, 0));
  await tester.pump();
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
    final path = _maskPathOf(container);
    if (path != null && path != previous) return path;
  }
  fail('erase stroke never persisted a new mask (previous: $previous)');
}

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('sm_maskgc_');
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    // Wide enough that no tool panel overflows (a pre-existing narrow-width
    // layout quirk in the Adjust header) so it can't mask the GC assertions.
    view.physicalSize = const Size(1500, 2000);
    view.devicePixelRatio = 2.0;
  });
  tearDown(() {
    imageCache.clear();
    imageCache.clearLiveImages();
    try {
      if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
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

  testWidgets(
    'the editor reclaims a superseded erase mask only once it is past undo '
    'reach, never while undo-reachable',
    (tester) async {
      // A real photo asset so decodeImageSize / the erase pipeline run for real.
      final asset = '${_tmp.path}/img_rex.png';
      File(
        asset,
      ).writeAsBytesSync(img.encodePng(img.Image(width: 16, height: 16)));

      final store = _RecordingMaskStore(baseDir: _tmp);
      final container = ProviderContainer(
        overrides: [
          editorControllerProvider.overrideWith(
            () => EditorController(
              StickerProject(
                id: 'p',
                name: 'Erase',
                frames: [
                  Frame(
                    id: 'f',
                    layers: [
                      ImageLayer(id: 'img', name: 'Rex', assetPath: asset),
                    ],
                  ),
                ],
              ),
            ),
          ),
          projectRepositoryProvider.overrideWithValue(
            ProjectRepository(baseDir: _tmp),
          ),
          maskStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildStickerTheme(),
            home: const EditorScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Arm the Erase tool on the photo.
      container.read(editorControllerProvider.notifier).selectLayer('img');
      container
          .read(editorControllerProvider.notifier)
          .setTool(EditorTool.erase);
      await tester.pumpAndSettle();

      // Two strokes → two mask files; the second supersedes the first.
      final p0 = await _eraseStroke(tester, container);
      final p1 = await _eraseStroke(tester, container, previous: p0);
      expect(p0, isNot(p1));
      expect(File(p0).existsSync(), isTrue);
      expect(File(p1).existsSync(), isTrue);

      // p0 is still one undo away: the GC has run on every state change but must
      // NOT have asked to delete it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(
        store.deleteRequests,
        isNot(contains(p0)),
        reason: 'an undo-reachable mask must never be deleted',
      );

      // Drop all history (as a project close/reopen would): p0 is now reachable
      // by neither the live document (p1) nor any undo/redo snapshot.
      final live = container.read(editorControllerProvider).project;
      expect(
        container.read(editorControllerProvider.notifier).isMaskReferenced(p0),
        isTrue,
        reason: 'sanity: still reachable before history is dropped',
      );
      container.read(editorControllerProvider.notifier).loadProject(live);
      await tester.pump(); // fires the editor's GC pass
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();

      // Now the editor reclaims p0 (superseded + past undo reach) and only p0.
      expect(
        store.deleteRequests,
        contains(p0),
        reason: 'a superseded mask past undo reach is reclaimed',
      );
      expect(
        store.deleteRequests,
        isNot(contains(p1)),
        reason: 'the live mask is never reclaimed',
      );
      expect(
        container.read(editorControllerProvider.notifier).isMaskReferenced(p0),
        isFalse,
      );
    },
  );
}
