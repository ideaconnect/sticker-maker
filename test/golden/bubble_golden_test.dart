@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/editor/widgets/bubble_view.dart';

/// Pixel goldens for the three bubble shapes, tail directions, and the caption
/// auto-fit (#78/#79) — the golden the BubblePainter doc always promised.
/// Regenerate with:
///   flutter test --tags golden --update-goldens
void main() {
  testWidgets('bubble shapes, tails and caption auto-fit', (tester) async {
    const bubbles = [
      BubbleLayer(id: 's', name: 's', text: 'Hello!'),
      BubbleLayer(
        id: 't',
        name: 't',
        text: 'Hmm…',
        shape: BubbleShape.thought,
        tail: Offset(0.5, 0.9),
      ),
      BubbleLayer(
        id: 'o',
        name: 'o',
        text: 'OMG!',
        shape: BubbleShape.shout,
        fillColor: Color(0xFFFFC53D),
        tail: Offset(-0.6, 0.8),
      ),
      // Upward tail + a caption long enough to trigger the auto-fit.
      BubbleLayer(
        id: 'l',
        name: 'l',
        text: 'This really long caption must stay inside the bubble!',
        tail: Offset(0.3, -1.6),
      ),
      BubbleLayer(
        id: 'c',
        name: 'c',
        text: 'Meanwhile…',
        shape: BubbleShape.caption,
      ),
      BubbleLayer(
        id: 'w',
        name: 'w',
        text: 'psst!',
        shape: BubbleShape.whisper,
        tail: Offset(0.6, 0.9),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF131019),
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('grid'),
              child: Container(
                color: const Color(0xFF131019),
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var row = 0; row < 3; row++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var col = 0; col < 2; col++)
                            Padding(
                              padding: const EdgeInsets.all(6),
                              child: BubbleView(
                                layer: bubbles[row * 2 + col],
                                scale: 1,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('grid')),
      matchesGoldenFile('goldens/bubbles.png'),
    );
  });
}
