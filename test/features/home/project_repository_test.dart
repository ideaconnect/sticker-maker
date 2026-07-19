import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/home/project_repository.dart';

void main() {
  late Directory dir;
  late ProjectRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sm_repo_');
    repo = ProjectRepository(baseDir: dir);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  StickerProject project(String id, {DateTime? updated}) =>
      StickerProject.empty(
        id: id,
        name: id.toUpperCase(),
        createdAt: DateTime.utc(2026),
      ).copyWith(updatedAt: updated);

  test('save then load round-trips', () async {
    await repo.save(project('alpha'));
    final loaded = await repo.load('alpha');
    expect(loaded, isNotNull);
    expect(loaded!.name, 'ALPHA');
  });

  test('load returns null for a missing project', () async {
    expect(await repo.load('nope'), isNull);
  });

  test('list returns saved projects, most-recently-updated first', () async {
    await repo.save(project('a', updated: DateTime.utc(2026)));
    await repo.save(project('b', updated: DateTime.utc(2026, 3)));
    await repo.save(project('c', updated: DateTime.utc(2026, 2)));
    final list = await repo.list();
    expect(list.map((p) => p.id), ['b', 'c', 'a']);
  });

  test('delete removes a project', () async {
    await repo.save(project('a'));
    await repo.delete('a');
    expect(await repo.load('a'), isNull);
    expect(await repo.list(), isEmpty);
  });

  test('list skips corrupt manifests', () async {
    await repo.save(project('good'));
    File('${dir.path}/projects/broken.json').writeAsStringSync('{ not json');
    final list = await repo.list();
    expect(list.map((p) => p.id), ['good']);
  });

  group('sweepOrphanAssets (#76)', () {
    late Directory assets;

    setUp(() {
      assets = Directory('${dir.path}/projects/assets')
        ..createSync(recursive: true);
    });

    File asset(String name) =>
        File('${assets.path}/$name')..writeAsBytesSync(const [1, 2, 3]);

    /// A project whose single frame references [imgName] (+ optional mask).
    StickerProject referencing(String id, String imgName, {String? mask}) =>
        project(id).copyWith(
          frames: [
            Frame(
              id: 'f_$id',
              layers: [
                ImageLayer(
                  id: 'l_$id',
                  name: 'Photo',
                  assetPath: '${assets.path}/$imgName',
                  maskPath: mask == null ? null : '${assets.path}/$mask',
                ),
              ],
            ),
          ],
        );

    test('deletes orphans, keeps referenced and foreign files', () async {
      await repo.save(referencing('a', 'img_a.png', mask: 'mask_a_1.png'));
      await repo.save(referencing('b', 'img_b.png'));
      asset('img_a.png');
      asset('mask_a_1.png');
      asset('img_b.png');
      asset('img_orphan.png');
      asset('mask_a_0.png'); // superseded erase mask
      asset('notes.txt'); // not ours — never touched

      final deleted = await repo.sweepOrphanAssets(minAge: Duration.zero);

      expect(deleted, 2);
      expect(asset('img_a.png').existsSync(), isTrue);
      expect(File('${assets.path}/mask_a_1.png').existsSync(), isTrue);
      expect(File('${assets.path}/img_b.png').existsSync(), isTrue);
      expect(File('${assets.path}/notes.txt').existsSync(), isTrue);
      expect(File('${assets.path}/img_orphan.png').existsSync(), isFalse);
      expect(File('${assets.path}/mask_a_0.png').existsSync(), isFalse);
    });

    test('a path shared by two projects survives either delete', () async {
      await repo.save(referencing('a', 'img_shared.png'));
      await repo.save(referencing('b', 'img_shared.png'));
      final shared = asset('img_shared.png');
      shared.setLastModifiedSync(
        DateTime.now().subtract(const Duration(hours: 1)),
      );

      await repo.delete('a'); // sweeps with the default minAge
      expect(shared.existsSync(), isTrue, reason: 'b still references it');

      await repo.delete('b');
      expect(shared.existsSync(), isFalse);
    });

    test('young files are never swept (in-flight import guard)', () async {
      asset('img_justnow.png'); // fresh mtime, no references at all
      final deleted = await repo.sweepOrphanAssets(); // default 10-min guard
      expect(deleted, 0);
      expect(File('${assets.path}/img_justnow.png').existsSync(), isTrue);
    });

    test('any corrupt manifest aborts the sweep entirely', () async {
      await repo.save(referencing('good', 'img_good.png'));
      asset('img_good.png');
      asset('img_orphan.png');
      File('${dir.path}/projects/broken.json').writeAsStringSync('{ nope');

      final deleted = await repo.sweepOrphanAssets(minAge: Duration.zero);

      expect(deleted, 0);
      expect(File('${assets.path}/img_orphan.png').existsSync(), isTrue);
    });
  });

  group('duplicate', () {
    StickerProject source() => StickerProject(
      id: 'src',
      name: 'Rex',
      currentFrameIndex: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      frames: const [
        Frame(
          id: 'src_f0',
          layers: [
            ImageLayer(
              id: 'src_l0',
              name: 'Photo',
              assetPath: '/assets/img_1.png',
              maskPath: '/assets/mask_1.png',
            ),
            TextLayer(id: 'src_l1', name: 'Cap', text: 'Hi', fontFamily: 'R'),
          ],
        ),
        Frame(
          id: 'src_f1',
          layers: [
            ImageLayer(
              id: 'src_l2',
              name: 'Photo',
              assetPath: '/assets/img_1.png',
            ),
          ],
        ),
      ],
    );

    Set<String> layerIds(StickerProject p) => {
      for (final f in p.frames) ...f.layers.map((l) => l.id),
    };

    test('saves a deep copy with fresh ids sharing asset paths', () async {
      await repo.save(source());
      final copy = await repo.duplicate('src');

      expect(copy, isNotNull);
      expect(copy!.name, 'Rex copy');
      expect(copy.id, isNot('src'));
      expect(copy.currentFrameIndex, 1);

      // Fresh ids for every frame and layer, none shared with the source.
      final frameIds = copy.frames.map((f) => f.id).toSet();
      expect(frameIds, hasLength(2));
      expect(frameIds.intersection({'src_f0', 'src_f1'}), isEmpty);
      expect(layerIds(copy), hasLength(3));
      expect(layerIds(copy).intersection(layerIds(source())), isEmpty);

      // Asset/mask files are shared, not copied.
      final img = copy.frames.first.layers.first as ImageLayer;
      expect(img.assetPath, '/assets/img_1.png');
      expect(img.maskPath, '/assets/mask_1.png');

      // The copy is persisted alongside the source.
      final loaded = await repo.load(copy.id);
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Rex copy');
      expect((await repo.list()).map((p) => p.id), contains('src'));
    });

    test('returns null for a missing project', () async {
      expect(await repo.duplicate('nope'), isNull);
    });

    test(
      'shared asset survives deleting one twin, dies with the last',
      () async {
        final assets = Directory('${dir.path}/projects/assets')
          ..createSync(recursive: true);
        final img = File('${assets.path}/img_1.png')
          ..writeAsBytesSync(const [1, 2, 3]);
        img.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 1)),
        );
        final withAsset = source().copyWith(
          frames: [
            Frame(
              id: 'src_f0',
              layers: [
                ImageLayer(
                  id: 'src_l0',
                  name: 'Photo',
                  assetPath: '${assets.path}/img_1.png',
                ),
              ],
            ),
          ],
        );
        await repo.save(withAsset);
        final copy = await repo.duplicate('src');

        await repo.delete('src'); // sweeps; the copy still references the file
        expect(img.existsSync(), isTrue);

        await repo.delete(copy!.id);
        expect(img.existsSync(), isFalse);
      },
    );
  });
}
