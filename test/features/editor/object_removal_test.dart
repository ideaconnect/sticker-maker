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
import 'package:sticker_maker/features/editor/widgets/editor_canvas.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/segmentation/ai_capability.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/engines/object/mobile_sam_engine.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';
import 'package:sticker_maker/features/segmentation/segmentation_registry.dart';

/// The tier-2 (SAM) escalation of a remove-object tap, driven for real through
/// the editor: capability-denied devices must never touch the object engine
/// and must see the honest capability toast; a hard engine failure must be
/// remembered so the engine is only ever paid for once (2026-07-19 review).

const String _capabilityToast =
    "Object removal AI isn't available on this device — "
    'use the Erase brush instead';

/// Counts every call; [onSegmentAt] injects behavior (throw / return null).
/// Tests assert on the counters, so even a swallowed exception can't hide an
/// unwanted invocation.
class _CountingObjectEngine implements ObjectSegmentationEngine {
  _CountingObjectEngine({this.onSegmentAt});

  final Future<AlphaMask?> Function()? onSegmentAt;
  int isAvailableCalls = 0;
  int precomputeCalls = 0;
  int segmentAtCalls = 0;

  int get totalCalls => isAvailableCalls + precomputeCalls + segmentAtCalls;

  @override
  Future<bool> isAvailable() async {
    isAvailableCalls++;
    return true;
  }

  @override
  Future<void> precompute(String imagePath) async {
    precomputeCalls++;
  }

  @override
  Future<AlphaMask?> segmentAt(
    String imagePath,
    List<PromptPoint> points,
  ) async {
    segmentAtCalls++;
    if (onSegmentAt != null) return onSegmentAt!();
    return null;
  }

  @override
  Future<void> dispose() async {}
}

/// Returns a canned in-memory mask so `_ensureWorkingMask` never touches disk
/// for the mask (the photo itself is a real fixture — `decodeImageSize` is
/// static and reads the file for real).
class _CannedMaskStore extends MaskStore {
  _CannedMaskStore(this.canned);

  final AlphaMask canned;

  @override
  Future<String> save(AlphaMask mask, {String? id}) async =>
      '/fake/mask_$id.png';

  @override
  Future<AlphaMask> load(String path) async => canned;
}

/// A store whose save always fails — models a transient IO error (disk full)
/// AFTER the engine already segmented successfully.
class _FailingSaveMaskStore extends _CannedMaskStore {
  _FailingSaveMaskStore(super.canned);

  int saveCalls = 0;

  @override
  Future<String> save(AlphaMask mask, {String? id}) async {
    saveCalls++;
    throw const FileSystemException('disk full');
  }
}

/// In-memory settings so the cutout panel resolves without host file IO.
class _MemorySettingsStore extends SettingsStore {
  String? _segId;

  @override
  Future<String?> segmentationModelId() async => _segId;

  @override
  Future<void> setSegmentationModelId(String id) async => _segId = id;
}

late Directory _tmp;

/// Writes a real, decodable 16×16 PNG fixture — a tap needs
/// `MaskStore.decodeImageSize(assetPath)` (static, real file IO) to succeed
/// before any removal tier runs.
Future<String> writePhotoFixture(WidgetTester tester) async {
  late String path;
  await tester.runAsync(() async {
    final png = await MaskStore.encodePng(AlphaMask.filled(16, 16, 255));
    final file = File('${_tmp.path}${Platform.pathSeparator}photo.png');
    await file.writeAsBytes(png, flush: true);
    path = file.path;
  });
  return path;
}

/// Pumps the editor with one photo layer that already has a cutout mask
/// (unlocking Remove-object mode). The canned working mask is one fully
/// opaque 16×16 blob, so ANY tap on the photo lands on the largest component
/// → `RemoveTapOutcome.subject` → tier-2 escalation.
Future<void> pumpEditor(
  WidgetTester tester, {
  required String photoPath,
  required ObjectSegmentationEngine engine,
  required AiCapability capability,
  MaskStore? maskStore,
}) async {
  final project = StickerProject(
    id: 'p',
    name: 'Cut',
    frames: [
      Frame(
        id: 'f',
        layers: [
          ImageLayer(
            id: 'img',
            name: 'Doggo',
            assetPath: photoPath,
            maskPath: '/fake/mask_img_seed.png',
          ),
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
        // No promptless engines — irrelevant to the tier-2 tests.
        segmentationRegistryProvider.overrideWithValue(
          const SegmentationRegistry([]),
        ),
        maskStoreProvider.overrideWithValue(
          maskStore ?? _CannedMaskStore(AlphaMask.filled(16, 16, 255)),
        ),
        settingsStoreProvider.overrideWithValue(_MemorySettingsStore()),
        objectSegmentationEngineProvider.overrideWithValue(engine),
        aiCapabilityProvider.overrideWith((ref) => capability),
      ],
      child: MaterialApp(
        theme: buildStickerTheme(),
        home: const EditorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Selects the photo layer, opens the Cut-out tool and arms Remove-object
/// mode (which fires the — possibly gated — SAM warm-up).
Future<void> armRemoveObjectMode(WidgetTester tester) async {
  await tester.tap(find.text('Layers'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Doggo').last);
  await tester.pumpAndSettle();
  // 'Cut out' shows both on the canvas badge (the seeded mask) and on the
  // tool tab; the tab is later in the tree.
  await tester.tap(find.text('Cut out').last);
  await tester.pumpAndSettle();
  final tab = find.text('Remove object');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Interleaves real-async waits (for the fixture file IO inside the tap
/// pipeline) with pumps until [text] shows — the repo's pattern for widget
/// tests whose production path does real IO.
Future<void> pumpUntilText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  for (var i = 0; i < 50; i++) {
    if (finder.evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(finder, findsOneWidget);
}

void main() {
  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('sm_object_removal_');
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(824, 1784);
    view.devicePixelRatio = 2.0;
  });
  tearDown(() {
    // The canvas may hold decoded images of the temp photo — release them so
    // Windows lets the delete through; tolerate a stubborn handle anyway.
    imageCache.clear();
    imageCache.clearLiveImages();
    try {
      if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
    } catch (_) {}
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets(
    'capability denied: the tap shows the honest capability toast and the '
    'object engine is never touched',
    (tester) async {
      final photoPath = await writePhotoFixture(tester);
      final engine = _CountingObjectEngine();
      await pumpEditor(
        tester,
        photoPath: photoPath,
        engine: engine,
        capability: (samAllowed: false, reason: 'test: 2 GiB device'),
      );

      await armRemoveObjectMode(tester);
      // The precompute warm-up (#85) must have been skipped by the gate.
      expect(engine.precomputeCalls, 0);

      // Tap the photo: the whole mask is one blob, so the tap escalates to
      // the SAM tier — which the capability gate must short-circuit.
      await tester.tap(find.byType(EditorCanvas));
      await pumpUntilText(tester, _capabilityToast);

      // Not the misleading tapped-the-subject message (2026-07-19 review).
      expect(
        find.text('That looks like your subject — use Erase for fine edits'),
        findsNothing,
      );
      expect(
        engine.totalCalls,
        0,
        reason: 'a denied device must never pay any engine cost',
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a hard engine failure is remembered: error toast once, then the '
      'capability toast without re-invoking the engine', (tester) async {
    final photoPath = await writePhotoFixture(tester);
    final engine = _CountingObjectEngine(
      onSegmentAt: () => throw StateError('broken ORT runtime'),
    );
    await pumpEditor(
      tester,
      photoPath: photoPath,
      engine: engine,
      capability: (samAllowed: true, reason: null),
    );

    await armRemoveObjectMode(tester);

    // First tap: the engine throws → generic error toast.
    await tester.tap(find.byType(EditorCanvas));
    await pumpUntilText(tester, "Couldn't remove that — try again");
    expect(engine.segmentAtCalls, 1);
    await tester.pumpAndSettle(); // let the toast dismiss

    // Second tap: the failure is remembered — immediate capability toast,
    // and the engine is NOT paid for again.
    await tester.tap(find.byType(EditorCanvas));
    await pumpUntilText(tester, _capabilityToast);
    expect(
      engine.segmentAtCalls,
      1,
      reason: 'a hard failure must not be retried at full cost per tap',
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a failure AFTER segmentation (mask save) stays retryable — only an '
    'engine throw may disable the SAM tier',
    (tester) async {
      final photoPath = await writePhotoFixture(tester);
      // First call: a 8×8 corner object (partial overlap, passes the subject
      // guard). Second call: null — deterministic "couldn't find" outcome
      // proving the engine was re-invoked at all.
      var call = 0;
      final engine = _CountingObjectEngine(
        onSegmentAt: () async {
          call++;
          if (call > 1) return null;
          final object = AlphaMask.filled(16, 16, 0);
          for (var y = 0; y < 8; y++) {
            for (var x = 0; x < 8; x++) {
              object.alpha[y * 16 + x] = 255;
            }
          }
          return object;
        },
      );
      final store = _FailingSaveMaskStore(AlphaMask.filled(16, 16, 255));
      await pumpEditor(
        tester,
        photoPath: photoPath,
        engine: engine,
        capability: (samAllowed: true, reason: null),
        maskStore: store,
      );
      await armRemoveObjectMode(tester);

      // First tap: segmentation succeeds, the save throws → generic error
      // toast, and the engine must NOT be blamed for the IO failure.
      await tester.tap(find.byType(EditorCanvas));
      await pumpUntilText(tester, "Couldn't remove that — try again");
      expect(engine.segmentAtCalls, 1);
      expect(store.saveCalls, 1, reason: 'the failure must come from save');
      await tester.pumpAndSettle();

      // Second tap: the tier is still live — the engine is paid again and
      // the capability toast never appears.
      await tester.tap(find.byType(EditorCanvas));
      await pumpUntilText(tester, "Couldn't find an object there");
      expect(
        engine.segmentAtCalls,
        2,
        reason: 'a transient save failure must not disable the SAM tier',
      );
      expect(find.text(_capabilityToast), findsNothing);
      await tester.pumpAndSettle();
    },
  );
}
