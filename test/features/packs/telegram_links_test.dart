import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/packs/telegram_links.dart';

void main() {
  group('newPackCommand', () {
    test('animated packs prefill /newvideo', () {
      final uri = TelegramLinks.newPackCommand(animated: true);
      expect(uri.scheme, 'tg');
      expect(uri.host, 'resolve');
      expect(uri.queryParameters['domain'], 'stickers');
      expect(uri.queryParameters['text'], '/newvideo');
      // The slash is percent-encoded in the serialized URI.
      expect(uri.toString(), contains('text=%2Fnewvideo'));
    });

    test('static packs prefill /newpack', () {
      final uri = TelegramLinks.newPackCommand(animated: false);
      expect(uri.queryParameters['text'], '/newpack');
    });
  });

  group('install links', () {
    test('web link points at addstickers', () {
      expect(
        TelegramLinks.installLink('my_pack').toString(),
        'https://t.me/addstickers/my_pack',
      );
    });

    test('app-scheme link carries the set name', () {
      final uri = TelegramLinks.installAppLink('my_pack');
      expect(uri.scheme, 'tg');
      expect(uri.host, 'addstickers');
      expect(uri.queryParameters['set'], 'my_pack');
    });
  });

  group('suggestShortName', () {
    test('lowercases and replaces spaces/punctuation with underscores', () {
      expect(TelegramLinks.suggestShortName('Happy Dogs!'), 'happy_dogs');
    });

    test('collapses runs and trims underscores', () {
      expect(TelegramLinks.suggestShortName('  Wow -- cats  '), 'wow_cats');
    });

    test('must start with a letter (leading digits/symbols dropped)', () {
      expect(TelegramLinks.suggestShortName('123 Doggo'), 'doggo');
    });

    test('falls back to "stickers" when nothing usable remains', () {
      expect(TelegramLinks.suggestShortName('12345'), 'stickers');
      expect(TelegramLinks.suggestShortName('🐶🎉'), 'stickers');
    });

    test('caps at 64 characters', () {
      final long = 'a' * 100;
      expect(TelegramLinks.suggestShortName(long).length, 64);
    });
  });
}
