import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/settings/settings_store.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/editor_screen.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';
import 'package:sticker_maker/features/segmentation/seg_model.dart';
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

/// In-memory settings so the model picker's persistence resolves inside the
/// widget test's fake-async zone — real `dart:io` file IO never completes there
/// (and would leave a locked temp file). Disk persistence is covered in
/// settings_store_test / seg_model_test, which run under real async.
class _MemorySettingsStore extends SettingsStore {
  String? _segId;

  @override
  Future<String?> segmentationModelId() async => _segId;

  @override
  Future<void> setSegmentationModelId(String id) async => _segId = id;
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
        // In-memory settings so the picker resolves without host file IO.
        settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
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

/// The Cut out panel scrolls (model picker above the CTA), so the button can sit
/// below the fold — bring it into view before tapping, as a user would.
///
/// The cut-out pipeline now hops mask work to helper isolates ([Isolate.run]),
/// which fake-async pumping can't drive: interleave real-async windows (the
/// isolate replies arrive on the real event loop) with pumps (fake-zone
/// microtasks flush) until the busy spinner is gone — the same pattern as
/// editor_canvas_test.dart. Harmless for taps that do no isolate work (the
/// "Working…" label never appears, so the loop exits on its first pump).
Future<void> tapPanelCta(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  for (var i = 0; i < 40; i++) {
    await tester.pump();
    if (find.text('Working…').evaluate().isEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
  }
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

    await tapPanelCta(tester, 'Remove background');

    // Mask produced, persisted and applied → the button is now the undo state.
    expect(find.text('Undo removal'), findsOneWidget);
    expect(find.text('Remove background'), findsNothing);
  });

  testWidgets('Undo removal clears the mask and restores Remove background', (
    tester,
  ) async {
    await pumpEditorWith(tester, SegmentationRegistry([_AlwaysOnEngine()]));
    await selectPhotoAndOpenCutout(tester);

    await tapPanelCta(tester, 'Remove background');
    expect(find.text('Undo removal'), findsOneWidget);

    await tapPanelCta(tester, 'Undo removal');
    expect(find.text('Remove background'), findsOneWidget);
  });

  testWidgets('a cutout unlocks the Remove object mode (#83)', (tester) async {
    await pumpEditorWith(tester, SegmentationRegistry([_AlwaysOnEngine()]));
    await selectPhotoAndOpenCutout(tester);

    // No mode switch before the cutout exists.
    expect(find.text('Remove object'), findsNothing);

    await tapPanelCta(tester, 'Remove background');
    expect(find.text('Remove object'), findsOneWidget);

    // Entering the mode swaps the panel to the tap hint (no model picker).
    // (tapPanelCta scrolls the tab into view — the panel is still scrolled
    // down to the CTA from the previous tap.)
    await tapPanelCta(tester, 'Remove object');
    expect(find.textContaining('Tap an unwanted object'), findsOneWidget);
    expect(find.text('AI MODEL'), findsNothing);

    // Back to the background mode restores the picker + CTA.
    await tapPanelCta(tester, 'Background');
    expect(find.text('AI MODEL'), findsOneWidget);
    expect(find.text('Undo removal'), findsOneWidget);
  });

  testWidgets('no available engine leaves the layer uncut (graceful)', (
    tester,
  ) async {
    await pumpEditorWith(tester, SegmentationRegistry([_UnavailableEngine()]));
    await selectPhotoAndOpenCutout(tester);

    await tapPanelCta(tester, 'Remove background');

    // Nothing was applied; the button stays in its idle state.
    expect(find.text('Remove background'), findsOneWidget);
    expect(find.text('Undo removal'), findsNothing);
  });

  testWidgets('model picker shows both engines, defaulting to Built-in AI', (
    tester,
  ) async {
    await pumpEditorWith(tester, SegmentationRegistry([_AlwaysOnEngine()]));
    await selectPhotoAndOpenCutout(tester);

    expect(find.text('AI MODEL'), findsOneWidget);
    expect(find.text(SegModel.builtin.label), findsOneWidget);
    expect(find.text(SegModel.u2net.label), findsOneWidget);
    expect(find.text(SegModel.builtin.tagline), findsOneWidget);
  });

  testWidgets('tapping a model row switches the active model', (tester) async {
    await pumpEditorWith(tester, SegmentationRegistry([_AlwaysOnEngine()]));
    await selectPhotoAndOpenCutout(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(EditorScreen)),
    );
    // Defaults to Built-in AI (loading resolves to the default via ?? builtin).
    expect(
      container.read(segModelProvider).asData?.value ?? SegModel.builtin,
      SegModel.builtin,
    );

    // The U²-Net row sits within the visible panel (above the CTA fold).
    await tester.tap(find.text(SegModel.u2net.label));
    await tester.pump(); // optimistic select() sets the state synchronously

    expect(container.read(segModelProvider).asData?.value, SegModel.u2net);
    // (On-disk persistence is covered in seg_model_test/settings_store_test,
    // which run under real async where dart:io file writes complete.)
  });

  testWidgets('the "?" opens the "Which AI model?" info sheet', (tester) async {
    await pumpEditorWith(tester, SegmentationRegistry([_AlwaysOnEngine()]));
    await selectPhotoAndOpenCutout(tester);

    await tester.tap(find.text('?'));
    await tester.pumpAndSettle();

    expect(find.text('Which AI model?'), findsOneWidget);
    expect(find.text(SegModel.builtin.blurb), findsOneWidget);
    expect(find.text(SegModel.u2net.blurb), findsOneWidget);
  });
}
