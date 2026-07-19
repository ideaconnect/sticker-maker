import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/frame.dart';
import 'ffmpeg_animation_encoder.dart';
import 'sticker_encoder.dart';
import 'sticker_renderer.dart';

/// The seam for **lossy** static WebP encoding. `package:image` only has the
/// lossless VP8L encoder, which balloons photo cutouts to 300–800 KB — far over
/// WhatsApp's 100 KB static cap — so the real implementation rides the bundled
/// FFmpeg ([FfmpegStaticWebpEncoder]); tests inject [FakeStaticWebpEncoder]
/// because FFmpegKit cannot run on the host.
abstract interface class StaticWebpEncoder {
  String get id;

  /// Whether the encoder is usable right now. Must not throw — returns false
  /// on any uncertainty (missing plugin, broken native lib).
  Future<bool> isAvailable();

  /// Encodes [pngBytes] (a transparent RGBA PNG) into a lossy static WebP at
  /// [quality] (libwebp 0–100), preserving the pixel dimensions and alpha.
  Future<Uint8List> encodePng(Uint8List pngBytes, {required int quality});
}

/// Single-frame lossy WebP via the bundled FFmpeg's `libwebp` encoder — the
/// static sibling of `FfmpegAnimWebpEncoder` (ADR 0004), sharing its runner,
/// probe and scratch-dir patterns: write the input PNG to a scratch dir, run
/// one ffmpeg command, read the encoded bytes back.
class FfmpegStaticWebpEncoder implements StaticWebpEncoder {
  FfmpegStaticWebpEncoder({FfmpegRunner? runner, this.scratchDir})
    : _runner = runner ?? ffmpegKitRunner;

  final FfmpegRunner _runner;

  /// Overrides the temp base dir (tests); defaults to the system temp dir.
  final Directory? scratchDir;
  bool? _available;

  @override
  String get id => 'ffmpeg-static-webp';

  /// Matches `libwebp` as the encoder-name column of an `-encoders` line. A
  /// plain `contains('libwebp')` would false-positive on the `libwebp_anim`
  /// line (its description also reads "libwebp WebP image").
  static final RegExp _libwebpEncoderLine = RegExp(
    r'^\s*\S+\s+libwebp\s',
    multiLine: true,
  );

  @override
  Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    try {
      final result = await _runner('-hide_banner -encoders');
      _available =
          result.success && _libwebpEncoderLine.hasMatch(result.output);
    } catch (_) {
      // Missing plugin (host tests) or a broken native lib → unavailable.
      _available = false;
    }
    return _available!;
  }

  /// The full command: same knobs as the animated variant (`-lossless 0
  /// -q:v`), minus animation-only args (`-loop`), on a single input image.
  @visibleForTesting
  String buildCommand(String inPath, String outPath, {required int quality}) =>
      '-y -i $inPath -c:v libwebp -lossless 0 -q:v $quality -an $outPath';

  @override
  Future<Uint8List> encodePng(
    Uint8List pngBytes, {
    required int quality,
  }) async {
    final base = scratchDir ?? await getTemporaryDirectory();
    final dir = Directory(
      '${base.path}/ffenc_${id}_${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    try {
      final inPath = '${dir.path}/in.png';
      File(inPath).writeAsBytesSync(pngBytes);
      final outPath = '${dir.path}/out.webp';
      final result = await _runner(
        buildCommand(inPath, outPath, quality: quality),
      );
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

/// Fits a static sticker under WhatsApp's byte cap at the **mandatory exact
/// 512×512 edge** (2026-07-19 review, top finding):
///
/// 1. Lossless VP8L first (pure Dart) — artifact-free and tiny for flat /
///    glyph stickers, so it stays the fast path.
/// 2. When lossless overshoots [whatsappMaxBytes] (photo cutouts routinely
///    encode to 300–800 KB), walk [qualityLadder] through the lossy encoder at
///    the same 512×512 — unlike `StickerEncoder.webpWithinBudget` this NEVER
///    downscales, because WhatsApp rejects any non-512 sticker.
/// 3. If even the lowest rung overshoots, throw a [StateError] naming the
///    sticker instead of shipping a pack WhatsApp would silently reject.
class StaticWebpBudgetEncoder {
  StaticWebpBudgetEncoder({StaticWebpEncoder? lossy})
    : _lossy = lossy ?? FfmpegStaticWebpEncoder();

  final StaticWebpEncoder _lossy;

  /// WhatsApp's static-sticker edge (px) — exact, never downscaled.
  static const int edge = 512;

  /// WhatsApp's static-sticker byte cap (§4 format table): 100 KB.
  static const int whatsappMaxBytes = 100 * 1024;

  /// Lossy qualities tried best-first once lossless overshoots.
  static const List<int> qualityLadder = [90, 80, 70, 60, 50, 40, 30];

  /// Encodes [frame] as a WhatsApp-compliant 512×512 static WebP within
  /// [maxBytes]. [stickerName] labels error messages so a failing pack export
  /// tells the user which sticker to simplify.
  Future<EncodedSticker> encode(
    Frame frame, {
    int maxBytes = whatsappMaxBytes,
    String stickerName = 'sticker',
  }) async {
    final lossless = await StickerEncoder.webp(frame);
    if (lossless.byteLength <= maxBytes) return lossless;

    if (!await _lossy.isAvailable()) {
      throw StateError(
        'Sticker "$stickerName" is ${lossless.byteLength ~/ 1024} KB lossless '
        'and the ${_lossy.id} lossy encoder is unavailable — cannot fit '
        "WhatsApp's ${maxBytes ~/ 1024} KB cap at $edge×$edge.",
      );
    }

    // Rendered at the (default) exact [edge] — the ladder varies quality only.
    final png = await StickerRenderer.renderPng(frame);
    for (final quality in qualityLadder) {
      final bytes = await _lossy.encodePng(png, quality: quality);
      if (bytes.length <= maxBytes) {
        return EncodedSticker(bytes: bytes, size: edge, format: 'webp');
      }
    }
    throw StateError(
      'Sticker "$stickerName" cannot fit under ${maxBytes ~/ 1024} KB at '
      '$edge×$edge even at the lowest lossy quality '
      '(${qualityLadder.last}) — simplify the sticker.',
    );
  }
}

final staticWebpBudgetEncoderProvider = Provider<StaticWebpBudgetEncoder>(
  (ref) => StaticWebpBudgetEncoder(),
);

/// Test double: records the qualities tried and returns [bytesFor]'s output
/// (default: `quality * 1024` zero bytes, so the 100 KB budget fits at q ≤ 100
/// deterministically without real encoding).
class FakeStaticWebpEncoder implements StaticWebpEncoder {
  FakeStaticWebpEncoder({
    this.available = true,
    Uint8List Function(int quality)? bytesFor,
  }) : _bytesFor = bytesFor ?? ((quality) => Uint8List(quality * 1024));

  final bool available;
  final Uint8List Function(int quality) _bytesFor;

  /// Qualities passed to [encodePng], in call order.
  final List<int> calls = [];
  Uint8List? lastPngBytes;

  @override
  String get id => 'fake-static-webp';

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Uint8List> encodePng(
    Uint8List pngBytes, {
    required int quality,
  }) async {
    calls.add(quality);
    lastPngBytes = pngBytes;
    return _bytesFor(quality);
  }
}
