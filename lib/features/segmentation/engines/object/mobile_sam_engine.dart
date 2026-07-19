import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../alpha_mask.dart';
import 'ort_graph.dart';

/// One prompt point in SOURCE-image pixel coordinates.
class PromptPoint {
  const PromptPoint(this.point, {this.foreground = true});

  final Offset point;

  /// true = "this is the object" (label 1), false = "not this" (label 0).
  final bool foreground;
}

/// Point-prompted object segmentation — deliberately a PARALLEL interface to
/// the promptless `SegmentationEngine` registry (#85): falling through from a
/// prompted engine to a promptless one would silently change what the result
/// means, so there is no fall-through chain here — one engine, or unavailable.
abstract interface class ObjectSegmentationEngine {
  Future<bool> isAvailable();

  /// Runs the heavy image-encoder pass eagerly (e.g. when the Remove-object
  /// mode is armed) so the first tap only pays the per-tap decoder cost.
  Future<void> precompute(String imagePath);

  /// Segments the object indicated by [points]. Returns a hard mask at the
  /// SOURCE image resolution (255 = object), or null when the engine can't
  /// run. Coordinates are source-image pixels.
  Future<AlphaMask?> segmentAt(String imagePath, List<PromptPoint> points);

  Future<void> dispose();
}

/// MobileSAM (Apache-2.0) via ONNX Runtime: a TinyViT encoder that runs ONCE
/// per photo (embedding cached in memory + on disk), and a light prompt
/// decoder per tap (#84/#85 — see model_conversion/convert_mobile_sam.py for
/// the exact graph contracts). The encoder session is disposed right after
/// its single pass to cap peak RAM; the decoder stays resident.
class MobileSamEngine implements ObjectSegmentationEngine {
  MobileSamEngine({
    Future<OrtGraph> Function(String assetKey)? graphFactory,
    AssetBundle? bundle,
    Directory? cacheDir,
  }) : _graphFactory = graphFactory ?? OrtGraphSession.fromAsset,
       _bundle = bundle ?? rootBundle,
       _cacheDirOverride = cacheDir;

  static const encoderAsset = 'assets/models/mobile_sam_encoder.onnx';
  static const decoderAsset = 'assets/models/mobile_sam_decoder.onnx';

  /// SAM's fixed input frame: images are resized so the longest side is 1024.
  static const int inputSide = 1024;

  /// The decoder's low-res logit grid (256²), which maps onto the PADDED
  /// 1024² frame — only the top-left (resized/4) region is valid.
  static const int lowResSide = 256;

  final Future<OrtGraph> Function(String assetKey) _graphFactory;
  final AssetBundle _bundle;
  final Directory? _cacheDirOverride;

  OrtGraph? _decoder;
  final Map<String, _Embedded> _memoryCache = {};

  @override
  Future<bool> isAvailable() async {
    try {
      await _bundle.load(encoderAsset);
      await _bundle.load(decoderAsset);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> precompute(String imagePath) async {
    try {
      await _ensureEmbedding(imagePath);
    } catch (_) {
      // Eager warm-up is best-effort; segmentAt reports real failures.
    }
  }

  @override
  Future<AlphaMask?> segmentAt(
    String imagePath,
    List<PromptPoint> points,
  ) async {
    if (points.isEmpty) return null;
    final embedded = await _ensureEmbedding(imagePath);

    // Prompt coords live in the RESIZED (longest-side-1024) frame. The resize
    // keeps aspect, so one factor per axis — computed per-axis anyway to stay
    // robust to rounding.
    final sx = embedded.resizedW / embedded.srcW;
    final sy = embedded.resizedH / embedded.srcH;
    // Official SAM ONNX usage: append one padding point with label -1.
    final n = points.length + 1;
    final coords = Float32List(n * 2);
    final labels = Float32List(n);
    for (var i = 0; i < points.length; i++) {
      coords[i * 2] = points[i].point.dx * sx;
      coords[i * 2 + 1] = points[i].point.dy * sy;
      labels[i] = points[i].foreground ? 1 : 0;
    }
    labels[n - 1] = -1; // pad point at (0,0)

    final decoder = _decoder ??= await _graphFactory(decoderAsset);
    final outputs = await decoder.run({
      'image_embeddings': (
        data: embedded.embedding,
        shape: [1, 256, 64, 64],
      ),
      'point_coords': (data: coords, shape: [1, n, 2]),
      'point_labels': (data: labels, shape: [1, n]),
      'mask_input': (
        data: Float32List(lowResSide * lowResSide),
        shape: [1, 1, lowResSide, lowResSide],
      ),
      'has_mask_input': (data: Float32List.fromList([0]), shape: [1]),
      // We never read the full-size `masks` output (megapixel float lists are
      // slow across the channel) — ask for a tiny one so the graph's final
      // resize is cheap, and upscale `low_res_masks` ourselves.
      'orig_im_size': (
        data: Float32List.fromList([lowResSide.toDouble(), lowResSide.toDouble()]),
        shape: [2],
      ),
    }, ['low_res_masks']);

    final logits = outputs['low_res_masks']!;
    return Isolate.run(
      () => _lowResToMask(
        logits,
        resizedW: embedded.resizedW,
        resizedH: embedded.resizedH,
        srcW: embedded.srcW,
        srcH: embedded.srcH,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _decoder?.dispose();
    _decoder = null;
    _memoryCache.clear();
  }

  // ------------------------------------------------------------ embedding
  Future<_Embedded> _ensureEmbedding(String imagePath) async {
    final file = File(imagePath);
    final stat = file.statSync();
    final key =
        '${stat.size}_${stat.modified.millisecondsSinceEpoch}_'
        '${imagePath.hashCode.toRadixString(16)}';

    final cached = _memoryCache[key];
    if (cached != null) return cached;

    final disk = await _loadDiskCache(key);
    if (disk != null) {
      _remember(key, disk);
      return disk;
    }

    // Pure-Dart decode/resize/pack off the UI isolate (a 2048² decode + HWC
    // pack is real jank territory on the main thread).
    final bytes = await file.readAsBytes();
    final prepared = await Isolate.run(() => _prepareInput(bytes));

    // Encoder: create, run once, dispose immediately — the TinyViT session +
    // arena is tens of MB we don't want resident.
    final encoder = await _graphFactory(encoderAsset);
    try {
      final outputs = await encoder.run({
        'input_image': (
          data: prepared.hwc,
          shape: [prepared.resizedH, prepared.resizedW, 3],
        ),
      }, ['image_embeddings']);
      final embedded = _Embedded(
        embedding: outputs['image_embeddings']!,
        srcW: prepared.srcW,
        srcH: prepared.srcH,
        resizedW: prepared.resizedW,
        resizedH: prepared.resizedH,
      );
      _remember(key, embedded);
      await _saveDiskCache(key, embedded);
      return embedded;
    } finally {
      await encoder.dispose();
    }
  }

  void _remember(String key, _Embedded value) {
    // Tiny LRU: an embedding is ~4 MB fp32 — keep at most two.
    if (_memoryCache.length >= 2 && !_memoryCache.containsKey(key)) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = value;
  }

  Future<Directory> _cacheDir() async {
    final base =
        _cacheDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/sam_embeddings');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<_Embedded?> _loadDiskCache(String key) async {
    try {
      final file = File('${(await _cacheDir()).path}/$key.bin');
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      final header = Int32List.view(bytes.buffer, 0, 4);
      final floats = Float32List.view(bytes.buffer, 16);
      return _Embedded(
        embedding: floats,
        srcW: header[0],
        srcH: header[1],
        resizedW: header[2],
        resizedH: header[3],
      );
    } catch (_) {
      return null; // corrupt cache entry — recompute
    }
  }

  Future<void> _saveDiskCache(String key, _Embedded e) async {
    try {
      final builder = BytesBuilder(copy: false)
        ..add(
          Int32List.fromList([
            e.srcW,
            e.srcH,
            e.resizedW,
            e.resizedH,
          ]).buffer.asUint8List(),
        )
        ..add(e.embedding.buffer.asUint8List(
          e.embedding.offsetInBytes,
          e.embedding.lengthInBytes,
        ));
      await File(
        '${(await _cacheDir()).path}/$key.bin',
      ).writeAsBytes(builder.takeBytes());
    } catch (_) {
      // Disk cache is an optimization — never fail the pipeline over it.
    }
  }

  // ----------------------------------------------------- isolate helpers
  /// Decode + resize (longest side [inputSide], aspect kept) + pack to HWC
  /// float32 RGB 0..255 — the exact encoder input contract.
  static _PreparedInput _prepareInput(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('could not decode the photo');
    }
    final srcW = decoded.width;
    final srcH = decoded.height;
    final scale = inputSide / (srcW > srcH ? srcW : srcH);
    final resizedW = (srcW * scale).round().clamp(1, inputSide);
    final resizedH = (srcH * scale).round().clamp(1, inputSide);
    final resized = img.copyResize(
      decoded,
      width: resizedW,
      height: resizedH,
      interpolation: img.Interpolation.linear,
    );
    final hwc = Float32List(resizedH * resizedW * 3);
    var i = 0;
    for (var y = 0; y < resizedH; y++) {
      for (var x = 0; x < resizedW; x++) {
        final p = resized.getPixel(x, y);
        hwc[i++] = p.rNormalized * 255;
        hwc[i++] = p.gNormalized * 255;
        hwc[i++] = p.bNormalized * 255;
      }
    }
    return _PreparedInput(
      hwc: hwc,
      srcW: srcW,
      srcH: srcH,
      resizedW: resizedW,
      resizedH: resizedH,
    );
  }

  /// Bilinear-samples the valid (resized/4) region of the 256² low-res logits
  /// up to source resolution; logit > 0 → 255.
  static AlphaMask _lowResToMask(
    Float32List logits, {
    required int resizedW,
    required int resizedH,
    required int srcW,
    required int srcH,
  }) {
    // The logit grid maps the PADDED 1024² frame: valid extent in grid units.
    final validW = resizedW * lowResSide / inputSide;
    final validH = resizedH * lowResSide / inputSide;
    final alpha = Uint8List(srcW * srcH);
    for (var y = 0; y < srcH; y++) {
      final v = (y + 0.5) * validH / srcH - 0.5;
      final v0 = v.floor().clamp(0, lowResSide - 1);
      final v1 = (v0 + 1).clamp(0, lowResSide - 1);
      final fv = (v - v0).clamp(0.0, 1.0);
      for (var x = 0; x < srcW; x++) {
        final u = (x + 0.5) * validW / srcW - 0.5;
        final u0 = u.floor().clamp(0, lowResSide - 1);
        final u1 = (u0 + 1).clamp(0, lowResSide - 1);
        final fu = (u - u0).clamp(0.0, 1.0);
        final top = logits[v0 * lowResSide + u0] * (1 - fu) +
            logits[v0 * lowResSide + u1] * fu;
        final bottom = logits[v1 * lowResSide + u0] * (1 - fu) +
            logits[v1 * lowResSide + u1] * fu;
        final logit = top * (1 - fv) + bottom * fv;
        if (logit > 0) alpha[y * srcW + x] = 255;
      }
    }
    return AlphaMask(width: srcW, height: srcH, alpha: alpha);
  }
}

class _PreparedInput {
  const _PreparedInput({
    required this.hwc,
    required this.srcW,
    required this.srcH,
    required this.resizedW,
    required this.resizedH,
  });

  final Float32List hwc;
  final int srcW;
  final int srcH;
  final int resizedW;
  final int resizedH;
}

class _Embedded {
  const _Embedded({
    required this.embedding,
    required this.srcW,
    required this.srcH,
    required this.resizedW,
    required this.resizedH,
  });

  final Float32List embedding;
  final int srcW;
  final int srcH;
  final int resizedW;
  final int resizedH;
}

/// The app's point-prompt engine. Kept as a plain provider (not a family) —
/// one resident decoder for the whole app.
final objectSegmentationEngineProvider = Provider<ObjectSegmentationEngine>(
  (ref) {
    final engine = MobileSamEngine();
    ref.onDispose(engine.dispose);
    return engine;
  },
);
