import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'alpha_mask.dart';

/// Persists an [AlphaMask] to disk as a PNG so it can back an
/// [ImageLayer.maskPath] non-destructively (the original photo is untouched).
///
/// The PNG carries the coverage in its **alpha channel** (RGB left white), which
/// makes render-time compositing a single `BlendMode.dstIn` draw — see
/// `StickerCanvas`.
class MaskStore {
  MaskStore({this.baseDir});

  /// Overridable in tests; defaults to the app documents directory.
  final Directory? baseDir;

  int _stamp() => DateTime.now().microsecondsSinceEpoch;

  Future<Directory> _assetsDir() async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/projects/assets');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Encodes [mask] and writes it into the project assets. [id] (a layer id)
  /// keeps the filename stable/greppable; a timestamp keeps successive cut-outs
  /// of the same layer distinct so the canvas image cache reloads.
  Future<String> save(AlphaMask mask, {String? id}) async {
    final png = await encodePng(mask);
    final dir = await _assetsDir();
    final tag = id == null ? '${_stamp()}' : '${id}_${_stamp()}';
    final dest = '${dir.path}/mask_$tag.png';
    await File(dest).writeAsBytes(png);
    return dest;
  }

  /// Loads a mask PNG back into an [AlphaMask] (reads its alpha channel).
  Future<AlphaMask> load(String path) async =>
      decodeAlpha(await File(path).readAsBytes());

  /// Best-effort deletion of a superseded mask PNG previously written by [save].
  /// A missing or locked file is ignored — the cold-launch orphan sweep
  /// ([ProjectRepository.sweepOrphanAssets]) remains the backstop. Callers MUST
  /// have established that [path] is no longer reachable by undo/redo, so a
  /// restored history state can never surface a now-missing mask.
  Future<void> deleteMask(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Locked / already-gone (e.g. a Windows file handle still open); the next
      // sweep retries.
    }
  }

  /// Decodes mask PNG [bytes] into an [AlphaMask].
  static Future<AlphaMask> decodeAlpha(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData();
    final w = image.width;
    final h = image.height;
    image.dispose();
    codec.dispose();
    if (data == null) throw StateError('failed to decode mask PNG');
    final rgba = data.buffer.asUint8List();
    final alpha = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      alpha[i] = rgba[i * 4 + 3];
    }
    return AlphaMask(width: w, height: h, alpha: alpha);
  }

  /// Decodes just the pixel dimensions of the image at [path] from its encoded
  /// header — no full-bitmap decode. A `getNextFrame` decode of a 2048² source
  /// would otherwise allocate ~16 MB just to read two ints; this reads only the
  /// header via [ui.ImageDescriptor], mirroring `EditorCanvas._loadDims`.
  static Future<ui.Size> decodeImageSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    buffer.dispose();
    final size = ui.Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    return size;
  }

  /// Converts an [AlphaMask] to PNG bytes: opaque white pixels whose alpha is
  /// the mask coverage. Uses `dart:ui`, so it runs on-device / in the test
  /// engine (not in a bare Dart VM).
  static Future<Uint8List> encodePng(AlphaMask mask) async {
    final rgba = Uint8List(mask.length * 4);
    for (var i = 0; i < mask.length; i++) {
      final o = i * 4;
      rgba[o] = 255;
      rgba[o + 1] = 255;
      rgba[o + 2] = 255;
      rgba[o + 3] = mask.alpha[i];
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      mask.width,
      mask.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw StateError('failed to encode mask PNG');
    }
    return data.buffer.asUint8List();
  }
}

/// Garbage-collects mask PNGs that a newer mask has superseded on a layer.
///
/// Every erase stroke / removal / cut-out writes a fresh timestamped
/// `mask_<id>_<stamp>.png` and points the layer at it; the previous file is then
/// only reachable through undo/redo history. This collector remembers those
/// superseded paths and, on demand, deletes each one that is no longer reachable
/// per a caller-supplied `isReferenced` predicate — so intermediate masks don't
/// pile up as orphans while a live undo entry can still restore them (#review
/// perf, 2026-07-19).
class SupersededMaskCollector {
  SupersededMaskCollector(this._store);

  final MaskStore _store;
  final Set<String> _pending = <String>{};

  /// Paths awaiting deletion (still undo/redo-reachable). Exposed for tests.
  @visibleForTesting
  Set<String> get pending => _pending;

  /// Records that [previous] was replaced by [current] on a layer. A null or
  /// unchanged previous path is ignored (nothing to reclaim).
  void supersede(String? previous, String current) {
    if (previous == null || previous == current) return;
    _pending.add(previous);
  }

  /// Deletes every pending path for which [isReferenced] returns false, then
  /// forgets it. Cheap to call often (e.g. on every editor state change): a
  /// no-op while nothing is pending, and a path that is still reachable simply
  /// stays queued for a later pass. Iterates a snapshot so a re-entrant call (or
  /// a [supersede]) during the `await` can't concurrently mutate the live set;
  /// [MaskStore.deleteMask] is idempotent, so a duplicated delete is harmless.
  Future<void> collect(bool Function(String path) isReferenced) async {
    if (_pending.isEmpty) return;
    for (final path in _pending.toList()) {
      if (isReferenced(path)) continue;
      await _store.deleteMask(path);
      _pending.remove(path);
    }
  }
}

final maskStoreProvider = Provider<MaskStore>((ref) => MaskStore());
