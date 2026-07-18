import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/app/app.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/settings/settings_store.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/templates/sticker_templates.dart';

void main() {
  group('sticker templates', () {
    test('there are at least 6 curated templates', () {
      expect(stickerTemplates.length, greaterThanOrEqualTo(6));
    });

    test('every template builds non-empty layers with unique ids', () {
      for (final t in stickerTemplates) {
        final layers = t.buildLayers();
        expect(layers, isNotEmpty, reason: '${t.id} has no layers');
        final ids = layers.map((l) => l.id).toSet();
        expect(ids.length, layers.length, reason: '${t.id} has duplicate ids');
      }
    });

    test('template ids are unique', () {
      final ids = stickerTemplates.map((t) => t.id).toSet();
      expect(ids.length, stickerTemplates.length);
    });

    test('previewProject yields one frame with the template layers', () {
      final t = stickerTemplates.first;
      final project = t.previewProject();
      expect(project.frames, hasLength(1));
      expect(project.frames.first.layers, isNotEmpty);
    });
  });

  group('Templates quickstart flow', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sm_tpl_');
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.physicalSize = const Size(824, 1784);
      view.devicePixelRatio = 2.0;
    });
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    testWidgets('Templates chip opens the picker and applies a template', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectRepositoryProvider.overrideWithValue(
              ProjectRepository(baseDir: tempDir),
            ),
            savedProjectsProvider.overrideWith((ref) => <StickerProject>[]),
            onboardingSeenProvider.overrideWith((ref) => true),
          ],
          child: const StickerMakerApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();

      // Picker sheet is up.
      expect(find.text('Pick a look — add your photo after.'), findsOneWidget);

      // Pick the "Woof!" template (card label; the preview renders "WOOF!").
      await tester.tap(find.text('Woof!'));
      await tester.pumpAndSettle();

      // Landed in the editor with the template's caption on the canvas.
      expect(find.text('512 × 512 · transparent'), findsOneWidget);
      expect(find.text('WOOF!'), findsWidgets);
    });
  });
}
