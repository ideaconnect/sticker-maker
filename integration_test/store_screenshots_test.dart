// Play Store screenshot harness (#52).
//
// Drives the REAL app on a REAL device through the eight poses of the capture
// plan in `docs/release/store-listing.md`, using the real photo fixture and the
// real on-device ML Kit cut-out. Taps are injected by Flutter inside the app
// process, which is the only thing that works on this project's test phone —
// `adb shell input tap` is silently swallowed there by a HyperOS security
// setting, so nothing driven from the shell can navigate the UI.
//
// ---------------------------------------------------------------------------
// Prerequisite: push the photo fixture (once per device)
//
//   MSYS_NO_PATHCONV=1 adb push assets/branding/pies.jpg \
//     /sdcard/Android/data/tech.idct.stickermaker/files/store_fixture.jpg
//   MSYS_NO_PATHCONV=1 adb shell chmod 0666 \
//     /sdcard/Android/data/tech.idct.stickermaker/files/store_fixture.jpg
//
// Without it the test fails loudly rather than capturing a mock.
//
// ---------------------------------------------------------------------------
// Two capture mechanisms, selected by --dart-define=SHOT_MODE=…
//
// (a) SHOT_MODE=driver (default) — `IntegrationTestWidgetsFlutterBinding
//     .takeScreenshot()` under `flutter drive`; `test_driver/integration_test
//     .dart` writes the PNGs. On Android this needs
//     `convertFlutterSurfaceToImage()`, which is a one-way switch that is known
//     to disturb later rendering on some engine versions — hence (b).
//
//     bash tools/store_shots/run_driver.sh
//
// (b) SHOT_MODE=logcat — the test prints a `STORE_SHOT_POSE:<name>` marker and
//     holds each pose still for [_holdForScreencap]; a shell loop tails logcat
//     and fires `adb exec-out screencap -p` on every marker. Captures the true
//     composited screen, no surface conversion.
//
//     bash tools/store_shots/run_logcat.sh
//
// Both produce `NN-name.png` in the output directory.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sticker_maker/app/app.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/layer_transform.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/settings/settings_store.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_processing.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';
import 'package:sticker_maker/features/segmentation/segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/segmentation_registry.dart';

// ---------------------------------------------------------------------- config

/// `driver` → `binding.takeScreenshot`; `logcat` → marker + hold for an
/// `adb exec-out screencap` fired by the shell runner.
const String _shotMode = String.fromEnvironment(
  'SHOT_MODE',
  defaultValue: 'driver',
);

/// Filename the harness pushes the photo to, inside the app's external files
/// dir (`/sdcard/Android/data/<pkg>/files/`).
const String _fixtureName = 'store_fixture.jpg';

/// How long each pose is held perfectly still. In `logcat` mode the shell loop
/// needs enough slack to see the marker and round-trip a `screencap`; in
/// `driver` mode this just lets implicit animations and image decodes land.
const Duration _holdForScreencap = Duration(milliseconds: 2600);
const Duration _holdForDriver = Duration(milliseconds: 900);

/// ML Kit's Subject Segmentation model is a Play-services module that may still
/// be downloading on a fresh device — give the first cut-out a generous budget.
const Duration _cutoutTimeout = Duration(minutes: 3);

late final IntegrationTestWidgetsFlutterBinding _binding;

/// `convertFlutterSurfaceToImage()` is a one-way, once-per-session switch.
bool _surfaceConverted = false;

/// Every pose actually captured, printed as a manifest at the end so the run log
/// is self-describing even if a later step fails.
final List<String> _captured = <String>[];

void _log(String message) {
  // ignore: avoid_print
  print(message);
}

// ------------------------------------------------------------------- utilities

/// Pumps real frames for [duration] — [WidgetTester.pumpAndSettle] returns as
/// soon as the tree is idle, which is not the same as "the screen has actually
/// been composited and is holding still".
Future<void> _hold(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 60));
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// Settles the tree, tolerating the never-idle case (a spinner, a looping
/// animation) instead of failing the whole run.
Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 80),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 6),
    );
  } catch (_) {
    await _hold(tester, const Duration(milliseconds: 400));
  }
}

/// Polls [finder] in real time until it matches or [timeout] elapses. Returns
/// whether it appeared — callers decide whether that is fatal.
Future<bool> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

Future<void> _tapText(WidgetTester tester, String label) async {
  final finder = find.text(label);
  expect(finder, findsWidgets, reason: 'expected "$label" to be tappable');
  await tester.tap(finder.first);
  await _settle(tester);
}

Future<void> _tapIcon(WidgetTester tester, IconData icon) async {
  final finder = find.byIcon(icon);
  expect(finder, findsWidgets, reason: 'expected icon $icon to be tappable');
  await tester.tap(finder.first);
  await _settle(tester);
}

/// Captures the current screen as `NN-name`.
///
/// The pose is settled, then held still, then captured. The `STORE_SHOT_POSE`
/// marker is printed BEFORE the hold so the logcat runner's `screencap` lands
/// inside it; `STORE_SHOT_DONE` closes the window.
Future<void> _shot(WidgetTester tester, String name) async {
  await _settle(tester);
  _log('STORE_SHOT_POSE:$name');
  await _hold(
    tester,
    _shotMode == 'logcat' ? _holdForScreencap : _holdForDriver,
  );
  if (_shotMode == 'driver') {
    if (!_surfaceConverted) {
      await _binding.convertFlutterSurfaceToImage();
      _surfaceConverted = true;
      await _hold(tester, const Duration(milliseconds: 300));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 60));
    await _binding.takeScreenshot(name);
  }
  _captured.add(name);
  _log('STORE_SHOT_DONE:$name');
}

// --------------------------------------------------------------------- fixture

/// The pushed photo, copied into the app's own project assets so it looks
/// exactly like an imported picture (and so the manifests we seed reference a
/// stable in-app path). Fails loudly when the fixture was never pushed.
Future<String> _installFixture() async {
  final external = await getExternalStorageDirectory();
  final pushed = File('${external!.path}/$_fixtureName');
  if (!pushed.existsSync()) {
    fail(
      'No $_fixtureName on the device. Push it first:\n'
      '  adb push assets/branding/pies.jpg ${external.path}/$_fixtureName\n'
      '  adb shell chmod 0666 ${external.path}/$_fixtureName',
    );
  }
  final docs = await getApplicationDocumentsDirectory();
  final assets = Directory('${docs.path}/projects/assets');
  if (!assets.existsSync()) assets.createSync(recursive: true);
  final dest = File('${assets.path}/img_store_pies.jpg');
  dest.writeAsBytesSync(pushed.readAsBytesSync());
  _log('STORE_SHOT_FIXTURE:${dest.path} (${dest.lengthSync()} bytes)');
  return dest.path;
}

Future<void> _wipe(String name) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}

/// Runs the REAL on-device segmentation engine over [photoPath] and persists the
/// cleaned-up mask. This is the same registry + clean-up chain the Cut out tool
/// uses; it exists so the seeded Home/pack content shows genuine cut-outs rather
/// than the raw photo. Retries while the ML Kit module downloads.
Future<String> _realCutoutMask(
  ProviderContainer container,
  String photoPath,
) async {
  final registry = container.read(segmentationRegistryProvider);
  SegmentationResult? result;
  final deadline = DateTime.now().add(_cutoutTimeout);
  while (result == null && DateTime.now().isBefore(deadline)) {
    result = await registry.segment(
      SegmentationRequest(imagePath: photoPath),
      preferredId: 'mlkit',
    );
    if (result == null) {
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
  expect(
    result,
    isNotNull,
    reason:
        'no segmentation engine produced a mask on this device — the store '
        'shots must show a real cut-out, so this is fatal',
  );
  final AlphaMask cleaned = MaskProcessing.process(
    result!.mask,
    const MaskProcessingOptions(),
  );
  final coverage = cleaned.coverage();
  _log(
    'STORE_SHOT_SEG:engine=${result.engineId} '
    'coverage=${coverage.toStringAsFixed(4)}',
  );
  expect(coverage, greaterThan(0.02), reason: 'the mask found a real subject');
  expect(
    coverage,
    lessThan(0.98),
    reason: 'the mask did not just select the whole frame',
  );
  return container.read(maskStoreProvider).save(cleaned, id: 'store_seed');
}

/// A saved sticker built straight from the model, used to populate Home's
/// "Recent" grid and the seeded pack. [extra] layers sit above the cut-out.
StickerProject _seedProject({
  required String id,
  required String name,
  required String photoPath,
  required String maskPath,
  double outlineWidth = 0,
  List<Layer> extra = const [],
  DateTime? at,
}) {
  final when = at ?? DateTime.now();
  return StickerProject(
    id: id,
    name: name,
    createdAt: when,
    updatedAt: when,
    frames: [
      Frame(
        id: '${id}_f0',
        layers: [
          ImageLayer(
            id: '${id}_l0',
            name: 'Photo',
            assetPath: photoPath,
            maskPath: maskPath,
            outlineWidth: outlineWidth,
          ),
          ...extra,
        ],
      ),
    ],
  );
}

/// Seeds four saved stickers (so Home is not an empty state) and one 3-sticker
/// static pack with emoji tags (so the pack manager shows a "Ready" badge).
Future<void> _seedLibrary(
  ProviderContainer container,
  String photoPath,
  String maskPath,
) async {
  final repo = container.read(projectRepositoryProvider);
  final now = DateTime.now();
  final seeds = <StickerProject>[
    _seedProject(
      id: 'store_seed_1',
      name: 'Park day',
      photoPath: photoPath,
      maskPath: maskPath,
      outlineWidth: 12,
      at: now.subtract(const Duration(minutes: 4)),
    ),
    _seedProject(
      id: 'store_seed_2',
      name: 'Walkies!',
      photoPath: photoPath,
      maskPath: maskPath,
      outlineWidth: 10,
      at: now.subtract(const Duration(minutes: 3)),
      extra: const [
        TextLayer(
          id: 'store_seed_2_l1',
          name: 'WALKIES!',
          text: 'WALKIES!',
          fontFamily: 'Bangers',
          fontSize: 54,
          transform: LayerTransform(
            position: Offset(256, 432),
            rotation: -0.09,
          ),
        ),
      ],
    ),
    _seedProject(
      id: 'store_seed_3',
      name: 'Good boy',
      photoPath: photoPath,
      maskPath: maskPath,
      at: now.subtract(const Duration(minutes: 2)),
      extra: const [
        BubbleLayer(
          id: 'store_seed_3_l1',
          name: 'Good boy!',
          text: 'Good boy!',
          transform: LayerTransform(position: Offset(250, 118)),
        ),
      ],
    ),
    _seedProject(
      id: 'store_seed_4',
      name: 'Party pup',
      photoPath: photoPath,
      maskPath: maskPath,
      outlineWidth: 14,
      at: now.subtract(const Duration(minutes: 1)),
      extra: const [
        TextLayer(
          id: 'store_seed_4_l1',
          name: '🎉',
          text: '🎉',
          fontFamily: 'Rubik',
          fontSize: 104,
          decorative: true,
          transform: LayerTransform(position: Offset(392, 128)),
        ),
      ],
    ),
  ];
  for (final project in seeds) {
    await repo.save(project);
  }

  await container
      .read(packRepositoryProvider)
      .save(
        StickerPack(
          id: 'store_seed_pack',
          name: 'Park Days',
          createdAt: now,
          updatedAt: now,
          stickers: const [
            PackSticker(id: 'ps_1', projectId: 'store_seed_1', emojis: ['🐶']),
            PackSticker(
              id: 'ps_2',
              projectId: 'store_seed_2',
              emojis: ['🦴', '🐾'],
            ),
            PackSticker(id: 'ps_3', projectId: 'store_seed_3', emojis: ['❤️']),
          ],
        ),
      );
}

// ------------------------------------------------------------------- the walk

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the eight Play Store phone screenshots', (tester) async {
    _log('STORE_SHOT_MODE:$_shotMode');

    // ---- state the run starts from -------------------------------------
    await _wipe('projects');
    await _wipe('packs');
    await SettingsStore().setOnboardingSeen(true);
    final photoPath = await _installFixture();

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // The one real ML Kit run; its mask backs both the seeded library and the
    // walkthrough sticker.
    final maskPath = await _realCutoutMask(container, photoPath);
    await _seedLibrary(container, photoPath, maskPath);

    // ---- 01 Home --------------------------------------------------------
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StickerMakerApp(),
      ),
    );
    await _settle(tester);
    expect(await _waitFor(tester, find.text('Recent stickers')), isTrue);
    // The grid decodes four cut-outs; give the image cache a moment.
    await _hold(tester, const Duration(seconds: 2));
    await _shot(tester, '01-home');

    // ---- into the editor with a real photo ------------------------------
    await _tapText(tester, 'New Sticker');
    expect(find.text('512 × 512 · transparent'), findsOneWidget);

    final editor = container.read(editorControllerProvider.notifier);
    // `addImageLayer` is the same entry point the gallery picker uses — the
    // picker itself is a platform UI Flutter cannot drive, so the harness hands
    // the photo straight in.
    final photoLayer = editor.addImageLayer(
      assetPath: photoPath,
      name: 'Photo',
    );
    editor.rename('Rex in the park');
    await _settle(tester);

    // ---- 02 Cut out (real on-device AI) ---------------------------------
    await _tapText(tester, 'Cut out');
    expect(find.text('AI Background Removal'), findsOneWidget);
    await _tapText(tester, 'Remove background');
    // The button flips to "Undo removal" exactly when the mask has been applied.
    final cutDone = await _waitFor(
      tester,
      find.text('Undo removal'),
      timeout: _cutoutTimeout,
    );
    expect(
      cutDone,
      isTrue,
      reason: 'the on-device cut-out never completed in the editor',
    );
    // Let the "Background removed" toast clear before capturing.
    await _hold(tester, const Duration(seconds: 3));
    await _shot(tester, '02-cutout');

    // ---- 03 Die-cut outline ---------------------------------------------
    await _tapText(tester, 'Adjust');
    editor.selectLayer(photoLayer.id);
    await _settle(tester);
    // Same call the "Die-cut outline" slider makes, then scroll the panel so
    // the slider itself is on screen at its new value.
    editor.updateImageOutline(photoLayer.id, width: 16);
    editor.endEdit();
    await _settle(tester);
    final outlineLabel = find.text('Die-cut outline');
    if (outlineLabel.evaluate().isNotEmpty) {
      await tester.ensureVisible(outlineLabel.first);
      await _settle(tester);
    }
    await _shot(tester, '03-outline');

    // ---- 04 Text & comic bubble -----------------------------------------
    await _tapText(tester, 'Text');
    await _tapText(tester, 'Add text');
    final caption = container.read(editorControllerProvider).selectedLayer;
    expect(caption, isA<TextLayer>());
    editor.updateTextLayer(caption!.id, text: 'WALKIES!', fontSize: 54);
    editor.updateTransform(
      caption.id,
      const LayerTransform(position: Offset(256, 436), rotation: -0.09),
    );
    editor.endEdit();
    await _settle(tester);
    // The bubble is added the way the UI does it (Layers → Add → Add bubble),
    // which also lands us in the bubble editor panel.
    await _tapText(tester, 'Layers');
    await _tapText(tester, 'Add');
    await _tapText(tester, 'Add bubble');
    final bubble = container.read(editorControllerProvider).selectedLayer;
    expect(bubble, isA<BubbleLayer>());
    editor.updateBubbleLayer(bubble!.id, text: "Who's a good boy?");
    editor.updateTransform(
      bubble.id,
      const LayerTransform(position: Offset(250, 112)),
    );
    editor.endEdit();
    await _settle(tester);
    await _shot(tester, '04-text-bubble');

    // ---- 05 Emoji --------------------------------------------------------
    await _tapText(tester, 'Layers');
    await _tapText(tester, 'Add');
    await _tapText(tester, 'Add emoji');
    expect(find.text('Add a sticker'), findsOneWidget);
    await _tapText(tester, '🎉');
    final placed = container.read(editorControllerProvider).selectedLayer;
    if (placed != null) {
      editor.updateTransform(
        placed.id,
        const LayerTransform(position: Offset(386, 126), scale: 0.9),
      );
      editor.endEdit();
    }
    await _settle(tester);
    // The placed emoji on the canvas …
    await _shot(tester, '05-emoji-placed');
    // … and the picker itself open over it, which is what the capture plan asks
    // for ("Emoji picker + a placed emoji").
    await _tapText(tester, 'Layers');
    await _tapText(tester, 'Add');
    await _tapText(tester, 'Add emoji');
    expect(find.text('Add a sticker'), findsOneWidget);
    await _shot(tester, '05-emoji');
    await tester.tapAt(const Offset(30, 60)); // dismiss the sheet
    await _settle(tester);

    // ---- 06 Frames / animation timeline ---------------------------------
    await _tapText(tester, 'Frames');
    expect(find.text('Animation frames'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await _tapIcon(tester, Icons.add);
    }
    // Nudge the caption per frame so the strip's thumbnails differ visibly.
    final project = container.read(editorControllerProvider).project;
    for (var i = 0; i < project.frameCount; i++) {
      editor.selectFrame(i);
      await tester.pump();
      final layers = container.read(editorControllerProvider).layers;
      final text = layers.whereType<TextLayer>().where((l) => !l.decorative);
      if (text.isNotEmpty) {
        editor.updateTransform(
          text.first.id,
          LayerTransform(
            position: Offset(256, 436 - i * 26),
            rotation: -0.09 + i * 0.13,
          ),
        );
        editor.endEdit();
      }
    }
    editor.selectFrame(1);
    editor.setFps(12);
    await _settle(tester);
    await _shot(tester, '06-frames');

    // ---- 07 Export screen ------------------------------------------------
    await _tapText(tester, 'Export');
    expect(await _waitFor(tester, find.text('Export sticker')), isTrue);
    // Wait for the real size estimate — it runs a full encode, so it is the
    // slowest thing on this screen.
    final estimated = await _waitFor(
      tester,
      find.textContaining(RegExp(r'\d+(\.\d+)?\s*(KB|MB)')),
      timeout: const Duration(seconds: 90),
    );
    if (!estimated) {
      _log('STORE_SHOT_WARN:size estimate never appeared on the export screen');
    }
    await _hold(tester, const Duration(seconds: 1));
    await _shot(tester, '07-export');

    // ---- 08 Sticker pack manager ----------------------------------------
    await _tapIcon(tester, Icons.chevron_left); // export → editor
    await _tapIcon(tester, Icons.chevron_left); // editor → home
    expect(await _waitFor(tester, find.text('Recent stickers')), isTrue);
    await _tapText(tester, 'Sticker packs');
    expect(await _waitFor(tester, find.text('YOUR PACKS')), isTrue);
    expect(
      find.text('Park Days'),
      findsOneWidget,
      reason: 'the seeded pack should be listed',
    );
    await _hold(tester, const Duration(seconds: 1));
    await _shot(tester, '08-packs');

    _log('STORE_SHOT_MANIFEST:${_captured.join(',')}');
    expect(_captured.length, 9, reason: 'all poses reached');
  });
}
