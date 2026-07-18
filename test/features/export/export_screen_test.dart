import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/export/export_screen.dart';

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
}
