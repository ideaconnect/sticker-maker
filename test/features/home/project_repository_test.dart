import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
