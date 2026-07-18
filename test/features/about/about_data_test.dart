import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/about/about_data.dart';

void main() {
  group('AboutInfo', () {
    test('privacy URL is https and has highlights', () {
      expect(AboutInfo.privacyUrl, startsWith('https://'));
      expect(AboutInfo.privacyHighlights, isNotEmpty);
      expect(AboutInfo.contactEmail, contains('@'));
    });
  });

  group('licenseNotices', () {
    test('every notice has complete attribution', () {
      expect(licenseNotices, isNotEmpty);
      for (final n in licenseNotices) {
        expect(n.name.trim(), isNotEmpty, reason: 'name');
        expect(n.by.trim(), isNotEmpty, reason: '${n.name} author');
        expect(n.license.trim(), isNotEmpty, reason: '${n.name} license');
        expect(n.use.trim(), isNotEmpty, reason: '${n.name} use');
        expect(n.category.trim(), isNotEmpty, reason: '${n.name} category');
      }
    });

    test('the bundled fonts are all attributed', () {
      final fonts = licenseNotices
          .where((n) => n.category == 'Fonts')
          .map((n) => n.name)
          .toList();
      for (final family in [
        'Plus Jakarta Sans',
        'Fredoka',
        'Bangers',
        'Luckiest Guy',
        'Pacifico',
        'Rubik',
      ]) {
        expect(fonts, contains(family), reason: '$family must be attributed');
      }
    });

    test('categories are de-duplicated in first-seen order', () {
      final cats = licenseCategories();
      expect(cats.toSet().length, cats.length, reason: 'no duplicates');
      expect(cats.first, 'Fonts');
      // Every notice belongs to a listed category.
      for (final n in licenseNotices) {
        expect(cats, contains(n.category));
      }
    });
  });
}
