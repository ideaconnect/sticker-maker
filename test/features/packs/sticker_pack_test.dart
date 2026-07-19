import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/export/compliance_validator.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';

PackSticker _sticker(String id, {List<String> emojis = const ['🐶']}) =>
    PackSticker(id: id, projectId: 'p_$id', emojis: emojis);

StickerPack _pack({List<PackSticker> stickers = const []}) =>
    StickerPack(id: 'pack1', name: 'Doggos', stickers: stickers);

void main() {
  group('StickerPack model', () {
    test('JSON round-trips', () {
      final pack = _pack(
        stickers: [
          _sticker('a'),
          _sticker('b', emojis: const ['🐱', '😹']),
        ],
      ).copyWith(animated: true, publisher: 'Me');
      final restored = StickerPack.fromJson(pack.toJson());
      expect(restored.id, pack.id);
      expect(restored.name, pack.name);
      expect(restored.publisher, 'Me');
      expect(restored.animated, isTrue);
      expect(restored.stickers, pack.stickers);
    });

    test('withSticker appends and de-dupes by projectId', () {
      final pack = _pack()
          .withSticker(_sticker('a'))
          .withSticker(_sticker('a'));
      expect(pack.count, 1, reason: 'same project not added twice');
    });

    test('withoutSticker / reorder / setEmojis', () {
      var pack = _pack(stickers: [_sticker('a'), _sticker('b'), _sticker('c')]);
      pack = pack.reorder(0, 2);
      expect(pack.stickers.map((s) => s.id), ['b', 'c', 'a']);
      pack = pack.withoutSticker('c');
      expect(pack.stickers.map((s) => s.id), ['b', 'a']);
      pack = pack.setEmojis('a', const ['🎉', '✨']);
      expect(pack.stickers.firstWhere((s) => s.id == 'a').emojis, ['🎉', '✨']);
    });

    test('validate flags too-few stickers and untagged ones', () {
      // 2 stickers (< 3), one untagged.
      final pack = _pack(
        stickers: [
          _sticker('a'),
          _sticker('b', emojis: const []),
        ],
      );
      final msgs = pack.validate().map((i) => i.message).join();
      expect(msgs, contains('at least 3'));
      expect(msgs, contains('emoji'));
    });

    test('a valid 3-sticker tagged pack has no issues', () {
      final pack = _pack(
        stickers: [_sticker('a'), _sticker('b'), _sticker('c')],
      );
      expect(pack.validate(), isEmpty);
    });

    test('a dangling projectId validates with an error → not ready', () {
      final pack = _pack(
        stickers: [_sticker('a'), _sticker('b'), _sticker('c')],
      );
      // 'p_c' was deleted: only a and b still resolve.
      final issues = pack.validate(knownProjectIds: {'p_a', 'p_b'});
      final missing = issues
          .where((i) => i.message.contains('missing its source project'))
          .toList();
      expect(missing, hasLength(1));
      expect(missing.single.severity, IssueSeverity.error);
      expect(missing.single.message, contains('1 sticker'));
      expect(
        issues.every((i) => i.severity != IssueSeverity.error),
        isFalse,
        reason: 'a broken pack must not count as ready',
      );
    });

    test('several dangling projectIds are counted in one plural issue', () {
      final pack = _pack(
        stickers: [_sticker('a'), _sticker('b'), _sticker('c')],
      );
      final issues = pack.validate(knownProjectIds: {'p_a'});
      final missing = issues
          .where((i) => i.message.contains('missing their source project'))
          .toList();
      expect(missing, hasLength(1));
      expect(missing.single.message, contains('2 stickers'));
    });

    test('knownProjectIds covering every sticker adds no issue', () {
      final pack = _pack(
        stickers: [_sticker('a'), _sticker('b'), _sticker('c')],
      );
      expect(pack.validate(knownProjectIds: {'p_a', 'p_b', 'p_c'}), isEmpty);
    });

    test('no-arg validate() keeps the historical behavior', () {
      // Same dangling pack, but the caller can't resolve projects: the
      // missing-project check is skipped rather than flagging everything.
      final pack = _pack(
        stickers: [_sticker('a'), _sticker('b'), _sticker('c')],
      );
      expect(pack.validate(), isEmpty);
    });

    test('withoutProject removes every slot referencing the project', () {
      final pack = _pack(
        stickers: [_sticker('a'), _sticker('b'), _sticker('c')],
      );
      final next = pack.withoutProject('p_b');
      expect(next.stickers.map((s) => s.projectId), ['p_a', 'p_c']);
      expect(
        pack.withoutProject('p_unknown').stickers,
        pack.stickers,
        reason: 'removing an absent project is a no-op',
      );
    });
  });

  group('PackRepository', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('sm_packs_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('save / load / list / delete round-trip', () async {
      final repo = PackRepository(baseDir: tmp);
      final pack = _pack(stickers: [_sticker('a')]);
      await repo.save(pack);

      final loaded = await repo.load('pack1');
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Doggos');
      expect(loaded.stickers.single.id, 'a');
      expect(loaded.updatedAt, isNotNull, reason: 'stamped on save');

      expect((await repo.list()).map((p) => p.id), ['pack1']);

      await repo.delete('pack1');
      expect(await repo.load('pack1'), isNull);
      expect(await repo.list(), isEmpty);
    });

    test('list skips a corrupt manifest', () async {
      final repo = PackRepository(baseDir: tmp);
      await repo.save(_pack(stickers: [_sticker('a')]));
      File('${tmp.path}/packs/broken.json').writeAsStringSync('{not json');
      expect((await repo.list()).length, 1);
    });
  });
}
