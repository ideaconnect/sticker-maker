@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/layer_transform.dart';
import 'package:sticker_maker/core/widgets/checkerboard.dart';
import 'package:sticker_maker/features/editor/widgets/sticker_canvas.dart';

/// Pixel goldens for the shared rendering surface. Tagged `golden` and excluded
/// from CI (see dart_test.yaml); regenerate with:
///   flutter test --tags golden --update-goldens
void main() {
  testWidgets('StickerCanvas composites layers in z-order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF131019),
          body: Center(
            child: SizedBox.square(
              dimension: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: const Stack(
                  fit: StackFit.expand,
                  children: [
                    Checkerboard(),
                    StickerCanvas(
                      frame: Frame(
                        id: 'g',
                        layers: [
                          ImageLayer(
                            id: 'i',
                            name: 'Rex',
                            assetPath: 'missing.png',
                            transform: LayerTransform(
                              position: Offset(256, 220),
                            ),
                          ),
                          TextLayer(
                            id: 't',
                            name: 'WOOF!',
                            text: 'WOOF!',
                            fontFamily: 'Bangers',
                            transform: LayerTransform(
                              position: Offset(256, 400),
                              rotation: -0.087,
                            ),
                          ),
                        ],
                      ),
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
      find.byType(StickerCanvas),
      matchesGoldenFile('goldens/canvas_compositing.png'),
    );
  });
}
