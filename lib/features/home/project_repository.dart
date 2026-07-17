import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/sticker_project.dart';

/// Persists [StickerProject]s as JSON manifests under the app documents
/// directory (`.../projects/<id>.json`). Image bytes are referenced by absolute
/// path in the manifest (written by the import service), so they survive
/// relaunches. Pass [baseDir] in tests to use a temp directory.
class ProjectRepository {
  ProjectRepository({Directory? baseDir}) : _baseOverride = baseDir;

  final Directory? _baseOverride;

  Future<Directory> _dir() async {
    final base = _baseOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/projects');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String id) => File('${dir.path}/$id.json');

  Future<void> save(StickerProject project) async {
    final dir = await _dir();
    await _file(dir, project.id).writeAsString(jsonEncode(project.toJson()));
  }

  /// All saved projects, most-recently-updated first. Corrupt manifests are
  /// skipped rather than throwing.
  Future<List<StickerProject>> list() async {
    final dir = await _dir();
    final result = <StickerProject>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final map = (jsonDecode(await entity.readAsString()) as Map)
            .cast<String, dynamic>();
        result.add(StickerProject.fromJson(map));
      } catch (_) {
        // Skip an unreadable / outdated manifest.
      }
    }
    DateTime key(StickerProject p) =>
        p.updatedAt ?? p.createdAt ?? DateTime.utc(1970);
    result.sort((a, b) => key(b).compareTo(key(a)));
    return result;
  }

  Future<StickerProject?> load(String id) async {
    final dir = await _dir();
    final file = _file(dir, id);
    if (!file.existsSync()) return null;
    final map = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, dynamic>();
    return StickerProject.fromJson(map);
  }

  Future<void> delete(String id) async {
    final dir = await _dir();
    final file = _file(dir, id);
    if (file.existsSync()) await file.delete();
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(),
);

/// The saved projects shown on Home. Invalidate after a save/delete to refresh.
final savedProjectsProvider = FutureProvider<List<StickerProject>>(
  (ref) => ref.watch(projectRepositoryProvider).list(),
);
