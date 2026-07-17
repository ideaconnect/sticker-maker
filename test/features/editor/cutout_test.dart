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
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';
import 'package:sticker_maker/features/segmentation/segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/segmentation_registry.dart';

/// A fake engine that always returns a full-coverage mask — lets us drive the
/// Cut-out flow deterministically on the host (real ML Kit needs a device).
class _AlwaysOnEngine implements SegmentationEngine {
  @override
  String get id => 'fake';
  @override
  String get label => 'Fake';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<SegmentationResult> segment(SegmentationRequest request) async =>
      SegmentationResult(mask: AlphaMask.filled(8, 8, 255), engineId: id);
}

/// An engine that never runs — proves the graceful "unavailable" path.
class _UnavailableEngine implements SegmentationEngine {
  @override
  String get id => 'none';
  @override
  String get label => 'None';
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<SegmentationResult> segment(SegmentationRequest request) async =>
      throw StateError('should not be called');
}

/// Returns a canned path without touching `dart:ui`, so the cut-out pipeline
/// completes under the widget test's fake-async zone (real PNG encoding is
/// covered separately in mask_store_test.dart).
class _FakeMaskStore extends MaskStore {
  @override
  Future<String> save(AlphaMask mask, {String? id}) async =>
      '/fake/mask_$id.png';
}

late Directory _tmp;

Future<void> pumpEditorWith(
  WidgetTester tester,
  SegmentationRegistry registry,
) async {
  const project = StickerProject(
    id: 'p',
    name: 'Cut',
    frames: [
      Frame(
        id: 'f',
        layers: [
          ImageLayer(id: 'img', name: 'Doggo', assetPath: '/no/such.png'),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        editorControllerProvider.overrideWith(() => EditorController(project)),
        projectRepositoryProvider.overrideWithValue(
          ProjectRepository(baseDir: _tmp),
        ),
        segmentationRegistryProvider.overrideWithValue(registry),
        maskStoreProvider.overrideWithValue(_FakeMaskStore()),
      ],
      child: MaterialApp(
        theme: buildStickerTheme(),
        home: const EditorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectPhotoAndOpenCutout(WidgetTester tester) async {
  await tester.tap(find.text('Layers'));
  await tester.pumpAndSettle();
  // 'Doggo' shows both on the canvas placeholder and in the layer row; the row
  // (later in the tree) is the selectable one.
  await tester.tap(find.text('Doggo').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cut out')); // tool tab
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('sm_cutout_');
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

  testWidgets('Remove background runs the pipeline and flips to Undo removal', (
    tester,
  ) async {
    await pumpEditorWith(tester, SegmentationRegistry([_AlwaysOnEngine()]));
    await selectPhotoAndOpenCutout(tester);

    expect(find.text('Remove background'), findsOneWidget);

    await tester.tap(find.text('Remove background'));
    await tester.pumpAndSettle();

    // Mask produced, persisted and applied → the button is now the undo state.
    expect(find.text('Undo removal'), findsOneWidget);
    expect(find.text('Remove background'), findsNothing);
  });

  testWidgets('Undo removal clears the mask and restores Remove background', (
    tester,
  ) async {
    await pumpEditorWith(tester, SegmentationRegistry([_AlwaysOnEngine()]));
    await selectPhotoAndOpenCutout(tester);

    await tester.tap(find.text('Remove background'));
    await tester.pumpAndSettle();
    expect(find.text('Undo removal'), findsOneWidget);

    await tester.tap(find.text('Undo removal'));
    await tester.pumpAndSettle();
    expect(find.text('Remove background'), findsOneWidget);
  });

  testWidgets('no available engine leaves the layer uncut (graceful)', (
    tester,
  ) async {
    await pumpEditorWith(tester, SegmentationRegistry([_UnavailableEngine()]));
    await selectPhotoAndOpenCutout(tester);

    await tester.tap(find.text('Remove background'));
    await tester.pumpAndSettle();

    // Nothing was applied; the button stays in its idle state.
    expect(find.text('Remove background'), findsOneWidget);
    expect(find.text('Undo removal'), findsNothing);
  });
}
