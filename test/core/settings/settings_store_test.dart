import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/settings/settings_store.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_settings_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('defaults to not-seen when no settings file exists', () async {
    expect(await SettingsStore(baseDir: tmp).onboardingSeen(), isFalse);
  });

  test('persists the onboarding-seen flag across instances', () async {
    await SettingsStore(baseDir: tmp).setOnboardingSeen(true);
    // A fresh instance reads the same persisted value.
    expect(await SettingsStore(baseDir: tmp).onboardingSeen(), isTrue);
  });

  test('can be reset back to false', () async {
    final store = SettingsStore(baseDir: tmp);
    await store.setOnboardingSeen(true);
    await store.setOnboardingSeen(false);
    expect(await store.onboardingSeen(), isFalse);
  });

  test('a corrupt settings file reads as not-seen (never bricks)', () async {
    File('${tmp.path}/settings.json').writeAsStringSync('{not valid json');
    expect(await SettingsStore(baseDir: tmp).onboardingSeen(), isFalse);
  });
}
