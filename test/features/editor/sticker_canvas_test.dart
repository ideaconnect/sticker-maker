import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/editor/widgets/sticker_canvas.dart';

Future<void> pumpCanvas(WidgetTester tester, Frame frame) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 320,
            child: StickerCanvas(frame: frame),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a visible text layer (stroke + fill)', (tester) async {
    await pumpCanvas(
      tester,
      const Frame(
        id: 'f',
        layers: [
          TextLayer(id: 't', name: 'Cap', text: 'WOOF!', fontFamily: 'Bangers'),
        ],
      ),
    );
    // StickerCaption draws the caption twice (outline + fill).
    expect(find.text('WOOF!'), findsNWidgets(2));
  });

  testWidgets('skips hidden layers', (tester) async {
    await pumpCanvas(
      tester,
      const Frame(
        id: 'f',
        layers: [
          TextLayer(
            id: 't',
            name: 'Cap',
            text: 'HIDDEN',
            fontFamily: 'Bangers',
            visible: false,
          ),
        ],
      ),
    );
    expect(find.text('HIDDEN'), findsNothing);
  });

  testWidgets('renders image layers as named placeholders in z-order', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      const Frame(
        id: 'f',
        layers: [
          ImageLayer(id: 'i', name: 'Rex', assetPath: 'p.png'),
          TextLayer(id: 't', name: 'Cap', text: 'Hi', fontFamily: 'Rubik'),
        ],
      ),
    );
    expect(find.text('Rex'), findsOneWidget); // placeholder label
    expect(find.text('Hi'), findsNWidgets(2)); // caption on top
  });
}
