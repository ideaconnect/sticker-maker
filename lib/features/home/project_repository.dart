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
    // A deleted project's unshared images/masks are now orphans — sweep them.
    await sweepOrphanAssets();
  }

  /// Deletes `img_*` / `mask_*` files in the shared `assets/` dir that no
  /// frame of any saved project references (#76). Reference counting is
  /// implicit: a file referenced by ANY manifest (frames legitimately share
  /// paths after duplication) is kept.
  ///
  /// Safety rules:
  /// - Call only when no editor session is active (project delete, cold
  ///   launch): in-memory undo stacks may point at mask files a saved
  ///   manifest no longer does.
  /// - Files younger than [minAge] are always kept — an import may not have
  ///   reached a (debounce-saved) manifest yet.
  /// - If ANY manifest fails to parse, the sweep aborts: a corrupt project's
  ///   references must not be mistaken for orphans.
  ///
  /// Returns the number of files deleted.
  Future<int> sweepOrphanAssets({
    Duration minAge = const Duration(minutes: 10),
  }) async {
    final dir = await _dir();
    final assets = Directory('${dir.path}/assets');
    if (!assets.existsSync()) return 0;

    final referenced = <String>{};
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        _collectAssetRefs(jsonDecode(await entity.readAsString()), referenced);
      } catch (_) {
        return 0; // corrupt manifest — its references are invisible, abort
      }
    }

    var deleted = 0;
    final now = DateTime.now();
    for (final entity in assets.listSync()) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      final sweepable = name.startsWith('img_') || name.startsWith('mask_');
      if (!sweepable || referenced.contains(name)) continue;
      try {
        if (now.difference(entity.statSync().modified) < minAge) continue;
        entity.deleteSync();
        deleted++;
      } catch (_) {
        // Locked or already-gone file — skip, next sweep retries.
      }
    }
    return deleted;
  }

  /// Recursively collects the basenames of every `assetPath` / `maskPath`
  /// string in a decoded manifest — schema-agnostic on purpose, so future
  /// layer types with image references stay covered as long as they use the
  /// same key names.
  static void _collectAssetRefs(Object? node, Set<String> out) {
    if (node is Map) {
      node.forEach((key, value) {
        if ((key == 'assetPath' || key == 'maskPath') && value is String) {
          out.add(_basename(value));
        } else {
          _collectAssetRefs(value, out);
        }
      });
    } else if (node is List) {
      for (final item in node) {
        _collectAssetRefs(item, out);
      }
    }
  }

  /// Last path segment, tolerant of both `/` and `\` separators.
  static String _basename(String path) => path.split('/').last.split('\\').last;
}

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(),
);

/// The saved projects shown on Home. Invalidate after a save/delete to refresh.
final savedProjectsProvider = FutureProvider<List<StickerProject>>(
  (ref) => ref.watch(projectRepositoryProvider).list(),
);
