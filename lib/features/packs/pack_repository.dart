import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'sticker_pack.dart';

/// Persists [StickerPack]s as JSON manifests under `<docs>/packs/<id>.json`.
/// Mirrors ProjectRepository.
class PackRepository {
  PackRepository({Directory? baseDir}) : _baseOverride = baseDir;

  final Directory? _baseOverride;

  Future<Directory> _dir() async {
    final base = _baseOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/packs');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> save(StickerPack pack) async {
    final dir = await _dir();
    final stamped = pack.copyWith(
      createdAt: pack.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await File(
      '${dir.path}/${pack.id}.json',
    ).writeAsString(jsonEncode(stamped.toJson()));
  }

  /// All packs, most-recently-updated first; corrupt files are skipped.
  Future<List<StickerPack>> list() async {
    final dir = await _dir();
    final packs = <StickerPack>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        packs.add(
          StickerPack.fromJson(
            jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>,
          ),
        );
      } catch (_) {
        // Skip a corrupt manifest rather than failing the whole list.
      }
    }
    packs.sort(
      (a, b) =>
          (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
    );
    return packs;
  }

  Future<StickerPack?> load(String id) async {
    final file = File('${(await _dir()).path}/$id.json');
    if (!file.existsSync()) return null;
    try {
      return StickerPack.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String id) async {
    final file = File('${(await _dir()).path}/$id.json');
    if (file.existsSync()) await file.delete();
  }
}

final packRepositoryProvider = Provider<PackRepository>(
  (ref) => PackRepository(),
);

final savedPacksProvider = FutureProvider<List<StickerPack>>(
  (ref) => ref.read(packRepositoryProvider).list(),
);
