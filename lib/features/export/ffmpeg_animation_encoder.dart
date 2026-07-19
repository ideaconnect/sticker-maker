import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'animation_encoder.dart';

/// Result of one ffmpeg invocation — success flag plus the session log (kept
/// for error surfaces and tests).
class FfmpegRunResult {
  const FfmpegRunResult({required this.success, required this.output});

  final bool success;
  final String output;
}

/// Runs one ffmpeg command string. The default implementation calls the
/// bundled FFmpegKit; host tests inject a fake so no plugin channel is touched.
typedef FfmpegRunner = Future<FfmpegRunResult> Function(String command);

/// The production [FfmpegRunner]: one FFmpegKit session per command. Shared by
/// the animated encoders below and [FfmpegStaticWebpEncoder].
Future<FfmpegRunResult> ffmpegKitRunner(String command) async {
  final session = await FFmpegKit.execute(command);
  return FfmpegRunResult(
    success: ReturnCode.isSuccess(await session.getReturnCode()),
    output: await session.getOutput() ?? '',
  );
}

/// Shared scaffolding for the two FFmpeg-backed [AnimationEncoder]s (ADR 0004):
/// writes the planned RGBA frames as a `%d.png` sequence in a scratch dir,
/// invokes ffmpeg over it, and reads the encoded bytes back. Timing comes from
/// the frames' (uniform, [AnimationPlanner]-produced) duration.
///
/// Both platforms require the 512-px edge EXACTLY (Telegram: one side 512;
/// WhatsApp: 512×512), so byte-budget searches vary only the [encode] `quality`
/// knob — never the raster size.
abstract class _FfmpegAnimationEncoder implements AnimationEncoder {
  _FfmpegAnimationEncoder({FfmpegRunner? runner, this.scratchDir})
    : _runner = runner ?? ffmpegKitRunner;

  final FfmpegRunner _runner;

  /// Overrides the temp base dir (tests); defaults to the system temp dir.
  final Directory? scratchDir;
  bool? _available;

  /// The output file extension and the codec-specific argument segment.
  String get extension;

  /// Codec arguments between the input sequence and the output path.
  @visibleForTesting
  String codecArgs({required int quality, required bool loop});

  /// The `-encoders` token whose presence proves this codec is usable.
  String get encoderToken;

  @override
  Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    try {
      final result = await _runner('-hide_banner -encoders');
      _available = result.success && result.output.contains(encoderToken);
    } catch (_) {
      // Missing plugin (host tests) or a broken native lib → unavailable.
      _available = false;
    }
    return _available!;
  }

  /// Builds the full command for [frames] living in [dir] as `%d.png`.
  @visibleForTesting
  String buildCommand(
    Directory dir,
    String outPath,
    List<RgbaFrame> frames, {
    required int quality,
    required bool loop,
  }) {
    final durationMs = frames.first.durationMs.clamp(1, 10000);
    final fps = (1000 / durationMs).clamp(1, 30).toStringAsFixed(3);
    return '-y -framerate $fps -i ${dir.path}/%d.png '
        '${codecArgs(quality: quality, loop: loop)} $outPath';
  }

  @override
  Future<Uint8List> encode(
    List<RgbaFrame> frames, {
    required int quality,
    required bool loop,
  }) async {
    assert(frames.isNotEmpty, 'need at least one frame');
    final base = scratchDir ?? await getTemporaryDirectory();
    final dir = Directory(
      '${base.path}/ffenc_${id}_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    try {
      for (var i = 0; i < frames.length; i++) {
        final f = frames[i];
        final image = img.Image.fromBytes(
          width: f.width,
          height: f.height,
          bytes: f.bytes.buffer,
          numChannels: 4,
        );
        File('${dir.path}/${i + 1}.png').writeAsBytesSync(img.encodePng(image));
      }
      final outPath = '${dir.path}/out.$extension';
      final command = buildCommand(
        dir,
        outPath,
        frames,
        quality: quality,
        loop: loop,
      );
      final result = await _runner(command);
      if (!result.success) {
        throw StateError('ffmpeg $id failed: ${_tail(result.output)}');
      }
      return File(outPath).readAsBytesSync();
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // Best-effort scratch cleanup; never mask the encode result.
      }
    }
  }

  static String _tail(String s) =>
      s.length <= 400 ? s : s.substring(s.length - 400);
}

/// WebM VP9 **with alpha** for Telegram video stickers (#67 / ANIM-2).
/// `yuva420p` makes libvpx-vp9 emit the alpha plane as a second VP9 stream in
/// Matroska BlockAdditions (AlphaMode=1) — the format Telegram accepts.
/// [AnimationEncoder.encode]'s `quality` is the target bitrate in **kbps**.
class FfmpegWebmVp9Encoder extends _FfmpegAnimationEncoder {
  FfmpegWebmVp9Encoder({super.runner, super.scratchDir});

  @override
  String get id => 'ffmpeg-webm-vp9';
  @override
  String get format => 'webm';
  @override
  String get extension => 'webm';
  @override
  String get encoderToken => 'libvpx-vp9';

  @override
  String codecArgs({required int quality, required bool loop}) =>
      // Constrained quality: cap the bitrate at the budget-derived target while
      // -crf keeps quality consistent. -auto-alt-ref 0 is required for alpha
      // (alt-ref frames corrupt the side alpha stream); row-mt speeds encoding.
      // Looping is a player-side behavior for stickers; no container flag.
      '-c:v libvpx-vp9 -pix_fmt yuva420p -b:v ${quality}K -crf 18 '
      '-deadline good -cpu-used 1 -row-mt 1 -auto-alt-ref 0 -an';
}

/// Animated WebP for WhatsApp animated stickers (#68 / ANIM-3).
/// [AnimationEncoder.encode]'s `quality` is libwebp's 0–100 quality knob.
class FfmpegAnimWebpEncoder extends _FfmpegAnimationEncoder {
  FfmpegAnimWebpEncoder({super.runner, super.scratchDir});

  @override
  String get id => 'ffmpeg-anim-webp';
  @override
  String get format => 'webp';
  @override
  String get extension => 'webp';
  @override
  String get encoderToken => 'libwebp_anim';

  @override
  String codecArgs({required int quality, required bool loop}) =>
      '-c:v libwebp_anim -lossless 0 -q:v $quality -loop ${loop ? 0 : 1} -an';
}
