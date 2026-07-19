import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
