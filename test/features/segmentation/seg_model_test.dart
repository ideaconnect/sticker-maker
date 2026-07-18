import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/settings/settings_store.dart';
import 'package:sticker_maker/features/segmentation/seg_model.dart';

void main() {
  group('SegModel mapping', () {
    test('ids and engine ids are the stable contract', () {
      expect(SegModel.builtin.engineId, 'mlkit');
      expect(SegModel.u2net.engineId, 'bundled');
      expect(SegModel.builtin.id, 'builtin');
      expect(SegModel.u2net.id, 'u2net');
    });

    test('fromId resolves known ids and defaults to builtin', () {
      expect(SegModel.fromId('u2net'), SegModel.u2net);
      expect(SegModel.fromId('builtin'), SegModel.builtin);
      expect(SegModel.fromId(null), SegModel.builtin);
      expect(SegModel.fromId('nonsense'), SegModel.builtin);
    });

    test('fromEngineId maps engine ids back, null for unknown', () {
      expect(SegModel.fromEngineId('mlkit'), SegModel.builtin);
      expect(SegModel.fromEngineId('bundled'), SegModel.u2net);
      expect(SegModel.fromEngineId('vision'), isNull);
    });
  });

  group('segModelProvider', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sm_segmodel_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    ProviderContainer containerOn(Directory dir) {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(SettingsStore(baseDir: dir)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('defaults to builtin when nothing is persisted', () async {
      final container = containerOn(tmp);
      expect(await container.read(segModelProvider.future), SegModel.builtin);
    });

    test('select updates state immediately and persists it', () async {
      final container = containerOn(tmp);
      await container.read(segModelProvider.future); // ensure built

      await container.read(segModelProvider.notifier).select(SegModel.u2net);
      expect(container.read(segModelProvider).asData?.value, SegModel.u2net);

      // A fresh container over the same settings dir reads the saved choice.
      final reopened = containerOn(tmp);
      expect(await reopened.read(segModelProvider.future), SegModel.u2net);
    });
  });
}
