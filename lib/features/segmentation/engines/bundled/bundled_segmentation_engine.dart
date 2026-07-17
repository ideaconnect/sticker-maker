import 'dart:io';
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
      final decoded = img.decodeImage(
        await File(request.imagePath).readAsBytes(),
      );
      if (decoded == null) {
        throw SegmentationException('could not decode image', engineId: id);
      }
      // Squash resize (both dims given) — U²-Net was trained on squashed input.
      final resized = img.copyResize(
        decoded,
        width: config.inputSize,
        height: config.inputSize,
      );
      final input = MaskTensor.packTensor(
        _rgbBytes(resized, config.inputSize),
        config.inputSize,
        config,
      );
      final segmenter = _segmenter ??= await _segmenterFactory(
        config.assetPath,
      );
      final output = await segmenter.infer(input, [
        1,
        3,
        config.inputSize,
        config.inputSize,
      ]);
      final mask = MaskTensor.unpackMask(
        output,
        config.inputSize,
        decoded.width,
        decoded.height,
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

  /// Extracts row-major RGB bytes (3/px) from a decoded [size]×[size] image.
  static Uint8List _rgbBytes(img.Image image, int size) {
    final rgb = Uint8List(size * size * 3);
    var i = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final p = image.getPixel(x, y);
        rgb[i++] = p.r.toInt();
        rgb[i++] = p.g.toInt();
        rgb[i++] = p.b.toInt();
      }
    }
    return rgb;
  }
}
