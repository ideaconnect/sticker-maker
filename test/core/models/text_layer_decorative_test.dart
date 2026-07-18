import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/layer.dart';

void main() {
  group('TextLayer.decorative (emoji / prop)', () {
    const caption = TextLayer(
      id: 't',
      name: 'Cap',
      text: 'Hi',
      fontFamily: 'Rubik',
    );

    test('captions are not decorative by default', () {
      expect(caption.decorative, isFalse);
    });

    test('copyWith toggles decorative', () {
      expect(caption.copyWith(decorative: true).decorative, isTrue);
    });

    test('JSON round-trips the flag', () {
      final emoji = caption.copyWith(text: '🐶', decorative: true);
      final restored = TextLayer.fromJson(emoji.toJson());
      expect(restored.decorative, isTrue);
      expect(restored, emoji);
    });

    test('legacy JSON without the key defaults to a caption', () {
      final json = caption.toJson()..remove('decorative');
      expect(TextLayer.fromJson(json).decorative, isFalse);
    });

    test('== distinguishes decorative', () {
      expect(caption == caption.copyWith(decorative: true), isFalse);
    });
  });
}
