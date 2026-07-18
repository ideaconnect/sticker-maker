import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/frame.dart';
import '../../core/models/sticker_project.dart';
import 'animation_encoder.dart';
import 'ffmpeg_animation_encoder.dart';
import 'sticker_encoder.dart';
import 'sticker_renderer.dart';

/// Rasterizes one model [Frame] to a straight-alpha [RgbaFrame]. Injectable so
/// host tests avoid `dart:ui` (which never completes under fake async).
typedef FrameRasterizer =
    Future<RgbaFrame> Function(Frame frame, int durationMs);

Future<RgbaFrame> _renderFrame(Frame frame, int durationMs) async {
  final image = await StickerRenderer.renderImage(frame);
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  if (data == null) throw StateError('failed to rasterize a frame');
  return RgbaFrame(
    bytes: data.buffer.asUint8List(),
    width: 512,
    height: 512,
    durationMs: durationMs,
  );
}

/// Drives a full animated export (#69 / ANIM-4): plan frame timing against the
/// target's [AnimationSpec], render the planned frames at 512², then encode
/// within the byte budget — WebM VP9+alpha for Telegram, animated WebP for
/// WhatsApp (ADR 0004). Both platforms pin the 512-px edge, so budget search
/// varies only quality/bitrate.
class AnimatedExportService {
  AnimatedExportService({
    AnimationEncoder? webmEncoder,
    AnimationEncoder? webpEncoder,
    FrameRasterizer? rasterizer,
  }) : _webm = webmEncoder ?? FfmpegWebmVp9Encoder(),
       _webp = webpEncoder ?? FfmpegAnimWebpEncoder(),
       _rasterize = rasterizer ?? _renderFrame;

  final AnimationEncoder _webm;
  final AnimationEncoder _webp;
  final FrameRasterizer _rasterize;

  /// Encodes [project]'s frames for [spec] at [fps]. Returns the encoded
  /// sticker; [BudgetedEncode.withinBudget] failures surface as a [StateError]
  /// so callers can show a "too complex to fit" message rather than sharing a
  /// file the platform will reject.
  Future<EncodedSticker> encode(
    StickerProject project,
    AnimationSpec spec, {
    double fps = 12,
  }) async {
    assert(project.frames.isNotEmpty, 'need at least one frame');
    final encoder = spec.format == 'webm' ? _webm : _webp;
    if (!await encoder.isAvailable()) {
      throw StateError('the ${spec.format} encoder is unavailable');
    }

    final plan = AnimationPlanner.plan(project.frames.length, fps, spec);
    final frames = <RgbaFrame>[
      for (final i in plan.frameIndices)
        await _rasterize(project.frames[i], plan.frameDurationMs),
    ];

    final result = await encodeWithinBudget(
      encoder,
      frames,
      spec,
      qualities: spec.format == 'webm'
          // Duration-aware bitrate: spend the whole 256 KB budget on quality.
          ? telegramBitrateLadderFor(plan.totalSeconds, maxBytes: spec.maxBytes)
          : whatsappQualityLadder,
    );
    if (!result.withinBudget) {
      throw StateError(
        'could not fit the animation under ${spec.maxBytes ~/ 1024} KB',
      );
    }
    return EncodedSticker(bytes: result.bytes, size: 512, format: spec.format);
  }
}

final animatedExportServiceProvider = Provider<AnimatedExportService>(
  (ref) => AnimatedExportService(),
);
