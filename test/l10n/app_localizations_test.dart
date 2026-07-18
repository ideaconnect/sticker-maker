import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/l10n/app_localizations.dart';

void main() {
  group('AppLocalizations scaffolding', () {
    test('supports English and Polish (and rejects others)', () {
      final codes = AppLocalizations.supportedLocales
          .map((l) => l.languageCode)
          .toSet();
      expect(codes, containsAll(<String>['en', 'pl']));
      expect(AppLocalizations.delegate.isSupported(const Locale('en')), isTrue);
      expect(AppLocalizations.delegate.isSupported(const Locale('pl')), isTrue);
      expect(
        AppLocalizations.delegate.isSupported(const Locale('fr')),
        isFalse,
      );
    });

    test('English strings load from the template ARB', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(en.appTitle, 'Sticker Maker');
      expect(en.newSticker, 'New Sticker');
      expect(en.seeAll, 'See all');
    });

    test('Polish strings are translated', () async {
      final pl = await AppLocalizations.delegate.load(const Locale('pl'));
      expect(pl.newSticker, 'Nowa naklejka');
      expect(pl.recentStickers, 'Ostatnie naklejki');
      expect(pl.stickerPacks, 'Paczki naklejek');
    });
  });

  testWidgets('AppLocalizations.of resolves the active locale at runtime', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context).newSticker),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Nowa naklejka'), findsOneWidget);
  });
}
