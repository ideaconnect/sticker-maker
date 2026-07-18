import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/packs/pack_dialogs.dart';

void main() {
  group('parseEmojiTags', () {
    test('splits space-separated emojis', () {
      expect(parseEmojiTags('😀 🐶 🎉'), ['😀', '🐶', '🎉']);
    });

    test('splits run-together emojis by grapheme cluster', () {
      expect(parseEmojiTags('😀🐶🎉'), ['😀', '🐶', '🎉']);
    });

    test('keeps a multi-codepoint emoji whole', () {
      // ❤️ is U+2764 U+FE0F — one grapheme cluster, one tag.
      expect(parseEmojiTags('❤️'), ['❤️']);
    });

    test('caps at 3 tags by default', () {
      expect(parseEmojiTags('😀🐶🎉🔥👍'), ['😀', '🐶', '🎉']);
    });

    test('respects a custom max', () {
      expect(parseEmojiTags('😀🐶🎉🔥', max: 2), ['😀', '🐶']);
    });

    test('blank / whitespace yields no tags', () {
      expect(parseEmojiTags('   '), isEmpty);
      expect(parseEmojiTags(''), isEmpty);
    });
  });
}
