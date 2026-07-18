import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/export/animated_export_service.dart';
import 'package:sticker_maker/features/export/animation_encoder.dart';
import 'package:sticker_maker/features/export/export_screen.dart';
import 'package:sticker_maker/features/export/sticker_encoder.dart';

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
}
