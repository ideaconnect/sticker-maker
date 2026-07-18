import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/packs_screen.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';

PackSticker _s(String id) =>
    PackSticker(id: id, projectId: 'p_$id', emojis: const ['🐶']);

Future<void> _pump(WidgetTester tester, List<StickerPack> packs) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [savedPacksProvider.overrideWith((ref) => packs)],
      child: MaterialApp(theme: buildStickerTheme(), home: const PacksScreen()),
    ),
  );
  await tester.pumpAndSettle();
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

  testWidgets('empty state invites creating the first pack', (tester) async {
    await _pump(tester, const []);

    expect(find.text('New pack'), findsOneWidget);
    expect(find.text('No packs yet'), findsOneWidget);
  });

  testWidgets('lists packs with a Ready / Draft status', (tester) async {
    await _pump(tester, [
      // 3 tagged stickers → compliant → Ready.
      StickerPack(
        id: 'ready',
        name: 'Happy Dogs',
        stickers: [_s('a'), _s('b'), _s('c')],
      ),
      // 1 sticker (< 3) → not compliant → Draft.
      StickerPack(id: 'draft', name: 'Work In Progress', stickers: [_s('a')]),
    ]);

    expect(find.text('Happy Dogs'), findsOneWidget);
    expect(find.text('Work In Progress'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });
}
