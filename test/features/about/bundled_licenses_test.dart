import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/about/bundled_licenses.dart';

void main() {
  group('bundled font licenses', () {
    test('every bundled license asset exists and is non-empty', () {
      for (final e in bundledLicenses) {
        final file = File(
          e.asset,
        ); // cwd is the package root under flutter test
        expect(file.existsSync(), isTrue, reason: '${e.asset} is missing');
        expect(file.readAsStringSync().trim(), isNotEmpty, reason: e.asset);
      }
    });

    test('OFL fonts carry the SIL Open Font License text', () {
      final ofl = bundledLicenses
          .where((e) => e.asset.contains('OFL'))
          .toList();
      expect(ofl, isNotEmpty);
      for (final e in ofl) {
        expect(
          File(e.asset).readAsStringSync(),
          contains('SIL Open Font License'),
          reason: e.asset,
        );
      }
    });

    test('the Apache-licensed font carries the Apache License text', () {
      final apache = bundledLicenses.firstWhere(
        (e) => e.asset.contains('Apache'),
      );
      expect(File(apache.asset).readAsStringSync(), contains('Apache License'));
    });

    test('every shipped font family has a bundled license', () {
      final covered = bundledLicenses.expand((e) => e.packages).toSet();
      for (final family in const [
        'Plus Jakarta Sans',
        'Fredoka',
        'Bangers',
        'Luckiest Guy',
        'Pacifico',
        'Rubik',
      ]) {
        expect(covered, contains(family), reason: '$family license missing');
      }
    });
  });
}
