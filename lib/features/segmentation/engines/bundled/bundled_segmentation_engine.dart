import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:image/image.dart' as img;

import '../../alpha_mask.dart';
import '../../segmentation_engine.dart';
import 'mask_tensor.dart';
import 'ort_segmenter.dart';
import 'segmenter.dart';

/// The bundled Apache-2.0 fallback engine (U²-Netp via ONNX Runtime). Used when
/// the system engine (ML Kit / Vision) is unavailable — e.g. no Play services —
/// and as a cross-platform consistency baseline. All inference is on-device.
///
/// The heavy lifting (decode → squash-resize → normalize → NCHW, and the whole
/// post-processing back to an [AlphaMask]) is pure Dart; only [Segmenter.infer]
/// touches the native runtime, so it is injected and faked in tests.
class BundledSegmentationEngine implements SegmentationEngine {
  BundledSegmentationEngine({
    this.config = u2netpConfig,
    Future<Segmenter> Function(String assetPath)? segmenterFactory,
    this.bundle,
  }) : _segmenterFactory = segmenterFactory ?? OrtSegmenter.fromAsset;

  final ModelConfig config;
  final Future<Segmenter> Function(String assetPath) _segmenterFactory;

  /// Overridable in tests; defaults to [rootBundle].
  final AssetBundle? bundle;

  Segmenter? _segmenter;

  @override
  String get id => 'bundled';

  @override
  String get label => 'Bundled U²-Netp';

  /// Available only when the model weights are actually bundled — until the
  /// `.onnx` asset ships, this returns false and the registry falls through.
  @override
  Future<bool> isAvailable() async {
    try {
      await (bundle ?? rootBundle).load(config.assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SegmentationResult> segment(SegmentationRequest request) async {
    try {
      final bytes = await File(request.imagePath).readAsBytes();
      final config = this.config;
      // Pure-Dart pre-processing (decode → squash-resize → normalize → pack)
      // runs off the UI isolate — a photo decode + NCHW pack froze the raster
      // thread so badly the "Working…" spinner couldn't animate. Only the
      // native [Segmenter.infer] stays on the root isolate (plugins are
      // root-isolate only). Same pattern as mobile_sam_engine.dart.
      final prepared = await Isolate.run(() => _prepareInput(bytes, config));
      final segmenter = _segmenter ??= await _segmenterFactory(
        config.assetPath,
      );
      final output = await segmenter.infer(prepared.tensor, [
        1,
        3,
        config.inputSize,
        config.inputSize,
      ]);
      // Post-processing (min-max normalize + bilinear upscale to the full
      // photo resolution) is the heaviest pure-Dart pass — also off the UI
      // isolate. Capture plain ints so the closure doesn't drag the input
      // tensor back across the isolate boundary.
      final inputSize = config.inputSize;
      final srcW = prepared.srcW;
      final srcH = prepared.srcH;
      final mask = await Isolate.run(
        () => MaskTensor.unpackMask(output, inputSize, srcW, srcH),
      );
      return SegmentationResult(mask: mask, engineId: id);
    } on SegmentationException {
      rethrow;
    } catch (e) {
      throw SegmentationException(
        'bundled segmentation failed: $e',
        engineId: id,
      );
    }
  }

  /// Pure-Dart pre-processing, run via [Isolate.run]: decode → squash resize
  /// (both dims given — U²-Net was trained on squashed input) → RGB bytes →
  /// NCHW pack. Static so the [Isolate.run] closure captures only plain
  /// sendable values ([bytes], [config]), never `this`.
  static ({Float32List tensor, int srcW, int srcH}) _prepareInput(
    Uint8List bytes,
    ModelConfig config,
  ) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      // String-only payload, so it crosses the isolate boundary intact.
      throw const SegmentationException(
        'could not decode image',
        engineId: 'bundled',
      );
    }
    final resized = img.copyResize(
      decoded,
      width: config.inputSize,
      height: config.inputSize,
    );
    return (
      tensor: MaskTensor.packTensor(
        _rgbBytes(resized, config.inputSize),
        config.inputSize,
        config,
      ),
      srcW: decoded.width,
      srcH: decoded.height,
    );
  }

  /// Extracts row-major RGB bytes (3/px) from a decoded [size]×[size] image.
  /// Uses the *normalized* channels so 16-bit and float source formats convert
  /// to 8-bit correctly instead of truncating (p.r would be 0…65535 for uint16).
  static Uint8List _rgbBytes(img.Image image, int size) {
    final rgb = Uint8List(size * size * 3);
    var i = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final p = image.getPixel(x, y);
        rgb[i++] = (p.rNormalized * 255).round().clamp(0, 255);
        rgb[i++] = (p.gNormalized * 255).round().clamp(0, 255);
        rgb[i++] = (p.bNormalized * 255).round().clamp(0, 255);
      }
    }
    return rgb;
  }
}
