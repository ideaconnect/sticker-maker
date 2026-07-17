import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';

import '../alpha_mask.dart';
import '../segmentation_engine.dart';

/// Google ML Kit Subject Segmentation engine (Android). Runs entirely
/// on-device; the model is delivered as an optional Play-services module
/// (downloaded on first use). When Play services or the model is unavailable,
/// [segment] throws a [SegmentationException] so the [SegmentationRegistry]
/// falls through to the bundled engine (#28).
class MlKitSegmentationEngine implements SegmentationEngine {
  MlKitSegmentationEngine();

  @override
  String get id => 'mlkit';

  @override
  String get label => 'ML Kit Subject Segmentation';

  SubjectSegmenter? _segmenter;

  SubjectSegmenter get _segmenterOrCreate => _segmenter ??= SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: false,
      enableForegroundConfidenceMask: true,
      enableMultipleSubjects: SubjectResultOptions(
        enableConfidenceMask: false,
        enableSubjectBitmap: false,
      ),
    ),
  );

  @override
  Future<bool> isAvailable() async =>
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<SegmentationResult> segment(SegmentationRequest request) async {
    final size = await _resolveSize(request);
    final width = size.$1;
    final height = size.$2;

    final SubjectSegmentationResult result;
    try {
      result = await _segmenterOrCreate.processImage(
        InputImage.fromFilePath(request.imagePath),
      );
    } on PlatformException catch (e) {
      // No Play services, model still downloading, unsupported ABI, …
      throw SegmentationException(
        e.message ?? 'ML Kit segmentation failed',
        engineId: id,
      );
    }

    final confidence = result.foregroundConfidenceMask;
    if (confidence == null) {
      throw SegmentationException(
        'ML Kit returned no confidence mask',
        engineId: id,
      );
    }
    if (confidence.length != width * height) {
      throw SegmentationException(
        'mask length ${confidence.length} != $width*$height',
        engineId: id,
      );
    }

    return SegmentationResult(
      mask: maskFromConfidence(confidence, width, height),
      engineId: id,
    );
  }

  /// Converts ML Kit's per-pixel foreground confidences (0.0 … 1.0) into an
  /// 8-bit [AlphaMask]. Pure and side-effect free — unit-tested directly.
  static AlphaMask maskFromConfidence(
    List<double> confidence,
    int width,
    int height,
  ) {
    final alpha = Uint8List(confidence.length);
    for (var i = 0; i < confidence.length; i++) {
      final v = (confidence[i] * 255).round();
      alpha[i] = v < 0 ? 0 : (v > 255 ? 255 : v);
    }
    return AlphaMask(width: width, height: height, alpha: alpha);
  }

  /// The mask is produced at the source image's resolution. Use the caller's
  /// hint when present, otherwise decode the image header for its dimensions.
  Future<(int, int)> _resolveSize(SegmentationRequest request) async {
    if (request.width != null && request.height != null) {
      return (request.width!, request.height!);
    }
    final bytes = await File(request.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = (image.width, image.height);
    image.dispose();
    codec.dispose();
    return size;
  }
}
