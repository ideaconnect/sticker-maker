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

  testWidgets(
    'outline stroke, shadow offset and tracking scale with fontSize so the '
    'preview matches the 512-px export (WYSIWYG)',
    (tester) async {
      // StickerRenderer._paintText is the WYSIWYG reference: at 512 px
      // (scale 1.0) it draws a 3.5-px stroke, an Offset(0, 4) shadow and
      // letterSpacing 1 alongside a scaled fontSize. StickerCaption must keep
      // the SAME stroke/font, shadow/font and tracking/font ratios at the
      // editor's smaller canvas scale, or the previewed outline is
      // proportionally chunkier than the exported sticker.
      const font = 48.0;

      // The outline layer is the Text whose style carries a stroke Paint; the
      // fill layer sets `color` instead (foreground == null).
      TextStyle outlineStyle() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.style!)
          .firstWhere((s) => s.foreground != null);

      // Reference: the 512-px export (scale 1.0).
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: StickerCaption(
            text: 'WOOF',
            fontFamily: 'Rubik',
            fontSize: font,
          ),
        ),
      );
      final ref = outlineStyle();
      expect(ref.foreground!.strokeWidth, 3.5, reason: 'renderer reference');
      expect(ref.shadows!.single.offset.dy, 4, reason: 'renderer reference');
      expect(ref.letterSpacing, 1, reason: 'renderer reference');

      // Editor canvas: a 320-px canvas / 512 ≈ 0.625. StickerCanvas pre-scales
      // fontSize and passes the canvas scale through `scale`.
      const editorScale = 0.625;
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: StickerCaption(
            text: 'WOOF',
            fontFamily: 'Rubik',
            fontSize: font * editorScale,
            scale: editorScale,
          ),
        ),
      );
      final preview = outlineStyle();

      double strokeRatio(TextStyle s) =>
          s.foreground!.strokeWidth / s.fontSize!;
      double shadowRatio(TextStyle s) =>
          s.shadows!.single.offset.dy / s.fontSize!;
      double trackingRatio(TextStyle s) => s.letterSpacing! / s.fontSize!;

      expect(strokeRatio(preview), closeTo(strokeRatio(ref), 1e-9));
      expect(shadowRatio(preview), closeTo(shadowRatio(ref), 1e-9));
      expect(trackingRatio(preview), closeTo(trackingRatio(ref), 1e-9));
    },
  );
}
