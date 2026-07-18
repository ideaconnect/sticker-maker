import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/widgets/sticker_caption.dart';

void main() {
  testWidgets('a caption stacks a stroke + fill (two Text layers)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: StickerCaption(text: 'WOOF', fontFamily: 'Rubik', fontSize: 40),
      ),
    );
    expect(find.text('WOOF'), findsNWidgets(2));
  });

  testWidgets('a decorative glyph renders once (no stroke/shadow)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: StickerCaption(
          text: '🐶',
          fontFamily: 'Rubik',
          fontSize: 96,
          decorative: true,
        ),
      ),
    );
    expect(find.text('🐶'), findsOneWidget);
  });
}
