import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/widgets/emoji_picker.dart';

void main() {
  group('kStickerEmojis', () {
    test('is a non-empty library with no duplicates', () {
      expect(kStickerEmojis, isNotEmpty);
      expect(kStickerEmojis.toSet().length, kStickerEmojis.length);
    });
  });

  testWidgets('picking an emoji returns it', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStickerTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => picked = await showEmojiPicker(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The library grid is up; tap the first emoji.
    final first = kStickerEmojis.first;
    await tester.tap(find.text(first));
    await tester.pumpAndSettle();

    expect(picked, first);
  });
}
