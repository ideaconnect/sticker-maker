import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sticker_maker/app/router.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/platform/platform_services.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/export/animated_export_service.dart';
import 'package:sticker_maker/features/export/animation_encoder.dart';
import 'package:sticker_maker/features/export/export_screen.dart';
import 'package:sticker_maker/features/export/static_webp_encoder.dart';
import 'package:sticker_maker/features/export/sticker_encoder.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';

import 'webp_fixtures.dart';

const _project = StickerProject(
  id: 'p',
  name: 'Doggo',
  frames: [
    Frame(
      id: 'f',
      layers: [
        TextLayer(id: 't', name: 'W', text: 'WOOF', fontFamily: 'Rubik'),
      ],
    ),
  ],
);

const _animatedProject = StickerProject(
  id: 'pa',
  name: 'Doggo Dance',
  frames: [
    Frame(
      id: 'f1',
      layers: [
        TextLayer(id: 't1', name: 'W', text: 'WOOF', fontFamily: 'Rubik'),
      ],
    ),
    Frame(
      id: 'f2',
      layers: [
        TextLayer(id: 't2', name: 'W', text: 'GRRR', fontFamily: 'Rubik'),
      ],
    ),
  ],
);

/// Keeps the size estimate away from the real FFmpeg plugin in host tests.
class _FakeAnimatedExport extends AnimatedExportService {
  @override
  Future<EncodedSticker> encode(
    StickerProject project,
    AnimationSpec spec, {
    double fps = 12,
  }) async => EncodedSticker(
    bytes: Uint8List.fromList(const [1, 2, 3]),
    size: 512,
    format: spec.format,
  );
}

/// Records the fps the screen asked to encode at (default 12 would prove the
/// project's fps was ignored).
class _RecordingFpsExport extends AnimatedExportService {
  double? lastFps;

  @override
  Future<EncodedSticker> encode(
    StickerProject project,
    AnimationSpec spec, {
    double fps = 12,
  }) async {
    lastFps = fps;
    return EncodedSticker(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      size: 512,
      format: spec.format,
    );
  }
}

/// Runs the REAL budget pipeline (with an injected fake lossy encoder) and
/// records what the screen's WhatsApp path actually emits.
class _RecordingBudgetEncoder extends StaticWebpBudgetEncoder {
  _RecordingBudgetEncoder({super.lossy});

  EncodedSticker? last;

  @override
  Future<EncodedSticker> encode(
    Frame frame, {
    int maxBytes = StaticWebpBudgetEncoder.whatsappMaxBytes,
    String stickerName = 'sticker',
  }) async => last = await super.encode(
    frame,
    maxBytes: maxBytes,
    stickerName: stickerName,
  );
}

/// Counts encodes and holds the webm (Telegram) result behind a gate so tests
/// can interleave a slow estimate with a fast one. WebP resolves immediately
/// with 3 bytes; webm waits for [webmGate] and returns 5 bytes.
class _RacingAnimatedExport extends AnimatedExportService {
  final webmGate = Completer<void>();
  int webmEncodes = 0;
  int webpEncodes = 0;

  @override
  Future<EncodedSticker> encode(
    StickerProject project,
    AnimationSpec spec, {
    double fps = 12,
  }) async {
    if (spec.format == 'webm') {
      webmEncodes++;
      await webmGate.future;
      return EncodedSticker(bytes: Uint8List(5), size: 512, format: 'webm');
    }
    webpEncodes++;
    return EncodedSticker(bytes: Uint8List(3), size: 512, format: 'webp');
  }
}

/// In-memory pack store so the "Add to sticker set" flow runs without file IO.
class _FakePackRepository extends PackRepository {
  _FakePackRepository([List<StickerPack> initial = const []]) {
    for (final p in initial) {
      _store[p.id] = p;
    }
  }

  final Map<String, StickerPack> _store = {};

  @override
  Future<void> save(StickerPack pack) async => _store[pack.id] = pack;
  @override
  Future<List<StickerPack>> list() async => _store.values.toList();
  @override
  Future<StickerPack?> load(String id) async => _store[id];
  @override
  Future<void> delete(String id) async => _store.remove(id);
}

/// Swallows the force-save the sticker-set flow does before referencing the
/// project by id.
class _FakeProjectRepository extends ProjectRepository {
  final saved = <StickerProject>[];

  @override
  Future<void> save(StickerProject project) async => saved.add(project);
}

/// Captures saveToDownloads calls so the download flow runs without the
/// platform channel.
class _FakePlatformServices extends PlatformServices {
  int saveCalls = 0;
  Uint8List? savedBytes;

  @override
  Future<String?> saveToDownloads(
    String fileName,
    String mimeType,
    Uint8List bytes,
  ) async {
    saveCalls++;
    savedBytes = bytes;
    return 'Downloads/$fileName';
  }
}

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

  testWidgets('previews the real project with the target picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorControllerProvider.overrideWith(
            () => EditorController(_project),
          ),
        ],
        child: MaterialApp(
          theme: buildStickerTheme(),
          home: const ExportScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Export sticker'), findsOneWidget); // title (unique)
    // Live preview renders the project's caption.
    expect(find.text('WOOF'), findsWidgets);
    // Target cards + the share action.
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Share sticker'), findsOneWidget);
  });

  testWidgets('a static (single-frame) project hides the animated toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorControllerProvider.overrideWith(
            () => EditorController(_project),
          ),
        ],
        child: MaterialApp(
          theme: buildStickerTheme(),
          home: const ExportScreen(),
        ),
      ),
    );
    await tester.pump();

    // Only animated projects show the Static/Animated toggle.
    expect(find.text('Animated'), findsNothing);
  });

  testWidgets('WhatsApp target swaps the share action for "Add to WhatsApp"', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorControllerProvider.overrideWith(
            () => EditorController(_project),
          ),
        ],
        child: MaterialApp(
          theme: buildStickerTheme(),
          home: const ExportScreen(),
        ),
      ),
    );
    await tester.pump();

    // Default target is Telegram → the plain share action.
    expect(find.text('Share sticker'), findsOneWidget);
    expect(find.text('Add to WhatsApp'), findsNothing);

    // WhatsApp needs a pack (min 3 stickers), so its action routes through the
    // pack builder rather than a one-off share.
    await tester.tap(find.text('WhatsApp'));
    await tester.pump();

    expect(find.text('Add to WhatsApp'), findsOneWidget);
    expect(find.text('Share sticker'), findsNothing);
  });

  testWidgets(
    'WhatsApp hides the Static/Animated toggle — packs are typed by project',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            editorControllerProvider.overrideWith(
              () => EditorController(_animatedProject),
            ),
            animatedExportServiceProvider.overrideWithValue(
              _FakeAnimatedExport(),
            ),
          ],
          child: MaterialApp(
            theme: buildStickerTheme(),
            home: const ExportScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Telegram (default): the animated project shows the mode toggle.
      expect(find.text('Animated'), findsOneWidget);
      expect(find.text('Static'), findsOneWidget);

      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();

      // WhatsApp: no toggle — an animated project always ships animated.
      expect(find.text('Animated'), findsNothing);
      expect(find.text('Static'), findsNothing);
      expect(find.text('Add to WhatsApp'), findsOneWidget);
    },
  );

  group('Add to sticker set', () {
    /// The export screen inside a router that owns the pack-detail destination,
    /// so the flow's final `pushNamed` resolves.
    Future<_FakePackRepository> pump(
      WidgetTester tester, {
      List<StickerPack> packs = const [],
    }) async {
      final repo = _FakePackRepository(packs);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ExportScreen()),
          GoRoute(
            path: '/pack/:id',
            name: Routes.packDetail,
            builder: (_, state) =>
                Scaffold(body: Text('pack:${state.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            editorControllerProvider.overrideWith(
              () => EditorController(_project),
            ),
            packRepositoryProvider.overrideWithValue(repo),
            projectRepositoryProvider.overrideWithValue(
              _FakeProjectRepository(),
            ),
          ],
          child: MaterialApp.router(
            theme: buildStickerTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    /// The flow keeps the primary button in its busy state (a looping spinner)
    /// for as long as the sheet is up, so `pumpAndSettle` would never return.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    /// Scrolls the bottom action into view and taps it.
    Future<void> tapAddToSet(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Add to sticker set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to sticker set'));
      await settle(tester);
    }

    testWidgets('is offered for every target except WhatsApp, whose primary '
        'action already is this flow', (tester) async {
      await pump(tester);

      // Telegram (default) — the standalone entry point is there.
      expect(find.text('Add to sticker set'), findsOneWidget);

      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();

      // WhatsApp's primary button IS the flow; no duplicate below Download.
      expect(find.text('Add to sticker set'), findsNothing);
      expect(find.text('Add to WhatsApp'), findsOneWidget);
    });

    testWidgets('creating a new set persists it and lands in the pack', (
      tester,
    ) async {
      final repo = await pump(tester);

      await tapAddToSet(tester);

      // Generic copy, not the WhatsApp pack-of-3 explanation.
      expect(find.text('Add to sticker set'), findsWidgets);
      expect(find.text('Add to a WhatsApp pack'), findsNothing);

      await tester.tap(find.text('Start a new set'));
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'Doggos');
      await tester.tap(find.text('Create'));
      await settle(tester);

      final packs = await repo.list();
      expect(packs, hasLength(1));
      expect(packs.single.name, 'Doggos');
      expect(packs.single.stickers.single.projectId, _project.id);
      expect(packs.single.animated, isFalse); // single-frame project
      expect(find.text('pack:${packs.single.id}'), findsOneWidget);
    });

    testWidgets('offers a compatible existing set to add to', (tester) async {
      final repo = await pump(
        tester,
        packs: [const StickerPack(id: 'pack1', name: 'Doggos')],
      );

      await tapAddToSet(tester);

      expect(find.text('OR ADD TO'), findsOneWidget);
      await tester.tap(find.text('Doggos'));
      await settle(tester);

      final pack = (await repo.list()).single;
      expect(pack.stickers.single.projectId, _project.id);
      expect(find.text('pack:pack1'), findsOneWidget);
    });
  });

  testWidgets('a stale slow estimate never overwrites a fresh fast one', (
    tester,
  ) async {
    final service = _RacingAnimatedExport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorControllerProvider.overrideWith(
            () => EditorController(_animatedProject),
          ),
          animatedExportServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          theme: buildStickerTheme(),
          home: const ExportScreen(),
        ),
      ),
    );
    await tester.pump();

    // Screen entry fired the (gated, slow) Telegram webm estimate.
    expect(service.webmEncodes, 1);
    expect(find.textContaining('Estimating'), findsOneWidget);

    // Switching to WhatsApp fires a fast webp estimate that lands first.
    await tester.tap(find.text('WhatsApp'));
    await tester.pump();
    await tester.pump();
    expect(find.text('~3 B · WEBP'), findsOneWidget);

    // The stale telegram encode completes AFTER — it must be discarded, not
    // overwrite the fresh label.
    service.webmGate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('~3 B · WEBP'), findsOneWidget);
    expect(find.textContaining('WEBM'), findsNothing);
    expect(find.textContaining('Estimating'), findsNothing);
  });

  testWidgets('download reuses the estimate encode instead of re-encoding', (
    tester,
  ) async {
    final service = _RacingAnimatedExport()..webmGate.complete();
    final platform = _FakePlatformServices();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorControllerProvider.overrideWith(
            () => EditorController(_animatedProject),
          ),
          animatedExportServiceProvider.overrideWithValue(service),
          platformServicesProvider.overrideWithValue(platform),
        ],
        child: MaterialApp(
          theme: buildStickerTheme(),
          home: const ExportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The entry estimate paid for one full (telegram webm) encode.
    expect(find.text('~5 B · WEBM'), findsOneWidget);
    expect(service.webmEncodes, 1);

    await tester.ensureVisible(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    // Same target/toggle/project revision → the cached bytes are reused.
    expect(service.webmEncodes, 1, reason: 'no second encode for the export');
    expect(platform.saveCalls, 1);
    expect(platform.savedBytes, hasLength(5));
    expect(find.textContaining('Saved to Downloads/'), findsOneWidget);

    // Let the toast's hold timer and exit animation finish.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'GIF + Static encodes only the current frame and drops the "animation" label',
    (tester) async {
      // A tall surface keeps every target card + the share button on-screen so
      // taps land without scrolling.
      TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first
          .physicalSize = const Size(
        824,
        2600,
      );

      List<Frame>? requestedFrames;
      Future<EncodedSticker> fakeGif(
        List<Frame> frames, {
        double fps = 12,
      }) async {
        requestedFrames = frames;
        return EncodedSticker(
          bytes: Uint8List.fromList(const [1, 2, 3]),
          size: 512,
          format: 'gif',
        );
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            editorControllerProvider.overrideWith(
              () => EditorController(_animatedProject),
            ),
            animatedExportServiceProvider.overrideWithValue(
              _FakeAnimatedExport(),
            ),
            gifEncoderProvider.overrideWithValue(fakeGif),
          ],
          child: MaterialApp(
            theme: buildStickerTheme(),
            home: const ExportScreen(),
          ),
        ),
      );
      await tester.pump();

      // Select GIF; the default mode is Animated, so the whole clip is encoded
      // and the button advertises an animation.
      await tester.tap(find.text('GIF'));
      await tester.pump();
      expect(requestedFrames, isNotNull);
      expect(requestedFrames!.length, _animatedProject.frames.length);
      expect(find.text('Share animation'), findsOneWidget);

      // Switch to Static: the encoder must receive exactly one frame and the
      // button must stop reading "Share animation".
      await tester.tap(find.text('Static'));
      await tester.pump();
      expect(requestedFrames!.length, 1);
      expect(requestedFrames!.single, _animatedProject.frames.first);
      expect(find.text('Share animation'), findsNothing);
      expect(find.text('Share sticker'), findsOneWidget);
    },
  );

  testWidgets("the project's fps reaches both the GIF and the animated encoder "
      '(not a hardcoded rate)', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first
        .physicalSize = const Size(
      824,
      2600,
    );

    final slow = _animatedProject.copyWith(fps: 2);
    double? gifFps;
    Future<EncodedSticker> fakeGif(
      List<Frame> frames, {
      double fps = 12,
    }) async {
      gifFps = fps;
      return EncodedSticker(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        size: 512,
        format: 'gif',
      );
    }

    final animated = _RecordingFpsExport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorControllerProvider.overrideWith(() => EditorController(slow)),
          animatedExportServiceProvider.overrideWithValue(animated),
          gifEncoderProvider.overrideWithValue(fakeGif),
        ],
        child: MaterialApp(
          theme: buildStickerTheme(),
          home: const ExportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Screen entry runs the Telegram (animated) estimate — it must encode at
    // the project's 2 fps, not the old hardcoded 12.
    expect(animated.lastFps, 2);

    // The GIF path forwards the same rate.
    await tester.tap(find.text('GIF'));
    await tester.pump();
    expect(gifFps, 2);
  });

  testWidgets('PNG and WebP targets hide the Static/Animated toggle', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first
        .physicalSize = const Size(
      824,
      2600,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorControllerProvider.overrideWith(
            () => EditorController(_animatedProject),
          ),
          animatedExportServiceProvider.overrideWithValue(
            _FakeAnimatedExport(),
          ),
        ],
        child: MaterialApp(
          theme: buildStickerTheme(),
          home: const ExportScreen(),
        ),
      ),
    );
    await tester.pump();

    // Telegram (default): the animated project shows the toggle.
    expect(find.text('Animated'), findsOneWidget);
    expect(find.text('Static'), findsOneWidget);

    // PNG is static-only — no toggle, so no "Animated" mode can be picked.
    await tester.tap(find.text('PNG'));
    await tester.pump();
    expect(find.text('Animated'), findsNothing);
    expect(find.text('Static'), findsNothing);

    // WebP is likewise static-only.
    await tester.tap(find.text('WebP'));
    await tester.pump();
    expect(find.text('Animated'), findsNothing);
    expect(find.text('Static'), findsNothing);
  });

  testWidgets('Telegram keeps its working Static/Animated toggle', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first
        .physicalSize = const Size(
      824,
      2600,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          editorControllerProvider.overrideWith(
            () => EditorController(_animatedProject),
          ),
          animatedExportServiceProvider.overrideWithValue(
            _FakeAnimatedExport(),
          ),
        ],
        child: MaterialApp(
          theme: buildStickerTheme(),
          home: const ExportScreen(),
        ),
      ),
    );
    await tester.pump();

    // Default Telegram + animated project defaults to Animated mode.
    expect(find.text('Share animation'), findsOneWidget);

    // Static → a single-frame sticker; Animated → back to the clip.
    await tester.tap(find.text('Static'));
    await tester.pump();
    expect(find.text('Share sticker'), findsOneWidget);
    expect(find.text('Share animation'), findsNothing);

    await tester.tap(find.text('Animated'));
    await tester.pump();
    expect(find.text('Share animation'), findsOneWidget);
    expect(find.text('Share sticker'), findsNothing);
  });

  testWidgets(
    'the WhatsApp path emits exactly 512 px even when lossless overshoots '
    '(lossy ladder, never a downscale)',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('sm_export_noisy_');
      addTearDown(() {
        imageCache.clear();
        imageCache.clearLiveImages();
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {
          // Windows may still hold an image handle — best effort.
        }
      });
      final noisy = writeNoisyPng(dir);
      final fakeLossy = FakeStaticWebpEncoder(
        bytesFor: (q) => smallValidWebp512(),
      );
      final recorder = _RecordingBudgetEncoder(lossy: fakeLossy);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            editorControllerProvider.overrideWith(
              () => EditorController(noisyProject('noisy', noisy.path)),
            ),
            staticWebpBudgetEncoderProvider.overrideWithValue(recorder),
          ],
          child: MaterialApp(
            theme: buildStickerTheme(),
            home: const ExportScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('WhatsApp'));
      await tester.pump();

      // The size estimate re-encodes with real file IO + dart:ui rasterizing —
      // interleave real-async waits with pumps until the encode lands.
      for (var i = 0; i < 600 && recorder.last == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }

      expect(recorder.last, isNotNull, reason: 'WhatsApp estimate completed');
      expect(
        recorder.last!.size,
        512,
        reason:
            "WhatsApp's exact-512 rule: the share path must never emit a "
            'sub-512 sticker',
      );
      expect(recorder.last!.byteLength, lessThanOrEqualTo(100 * 1024));
      expect(
        fakeLossy.calls,
        isNotEmpty,
        reason: 'noise overshoots losslessly → the lossy ladder engaged',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
