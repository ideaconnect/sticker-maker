import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/models/frame.dart';
import 'sticker_renderer.dart';

/// An encoded sticker ready to save / share.
class EncodedSticker {
  const EncodedSticker({
    required this.bytes,
    required this.size,
    required this.format,
  });

  final Uint8List bytes;

  /// The square edge length actually used (may be reduced to fit a budget).
  final int size;

  /// Lower-case file extension / format id, e.g. `png`.
  final String format;

  int get byteLength => bytes.length;
}

/// Static sticker encoders. PNG and (lossless, transparent) WebP are pure Dart;
/// the budget search downscales until the output fits a per-target byte cap
/// (WhatsApp static ≤ 100 KB, etc.). Animated GIF ships here too; animated WebP
/// and WebM VP9 are the remaining native encoders (#42b).
abstract final class StickerEncoder {
  StickerEncoder._();

  /// Candidate square sizes, largest first, tried by the budget search.
  static const List<int> defaultSizes = [512, 448, 384, 320, 256, 192, 128];

  /// Encodes [frame] to a transparent PNG at [size].
  static Future<EncodedSticker> png(Frame frame, {int size = 512}) async {
    final bytes = await StickerRenderer.renderPng(frame, size: size);
    return EncodedSticker(bytes: bytes, size: size, format: 'png');
  }

  /// Encodes [frame] to PNG at the largest [sizes] that fits [maxBytes]; if none
  /// fit, returns the smallest candidate (the best effort under the cap).
  static Future<EncodedSticker> pngWithinBudget(
    Frame frame, {
    required int maxBytes,
    List<int> sizes = defaultSizes,
  }) async {
    final chosen = await fitToBudget(
      (size) => StickerRenderer.renderPng(frame, size: size),
      maxBytes: maxBytes,
      sizes: sizes,
    );
    return EncodedSticker(
      bytes: chosen.bytes,
      size: chosen.size,
      format: 'png',
    );
  }

  /// Encodes [frame] to a transparent, lossless **WebP** at [size] — the format
  /// WhatsApp and Telegram require for static stickers. Pure Dart (VP8L via
  /// `package:image`), so no native/FFI dependency; alpha is preserved.
  static Future<EncodedSticker> webp(Frame frame, {int size = 512}) async {
    final bytes = await _webpBytes(frame, size);
    return EncodedSticker(bytes: bytes, size: size, format: 'webp');
  }

  /// WebP at the largest [sizes] fitting [maxBytes] (e.g. WhatsApp's 100 KB).
  static Future<EncodedSticker> webpWithinBudget(
    Frame frame, {
    required int maxBytes,
    List<int> sizes = defaultSizes,
  }) async {
    final chosen = await fitToBudget(
      (size) => _webpBytes(frame, size),
      maxBytes: maxBytes,
      sizes: sizes,
    );
    return EncodedSticker(
      bytes: chosen.bytes,
      size: chosen.size,
      format: 'webp',
    );
  }

  static Future<Uint8List> _webpBytes(Frame frame, int size) async {
    final image = await _renderRgba(frame, size);
    return img.encodeWebP(image);
  }

  /// Renders [frame] to a `package:image` RGBA [img.Image] at [size]. Shared by
  /// the WebP and GIF encoders. [frameDurationMs] stamps animation timing.
  static Future<img.Image> _renderRgba(
    Frame frame,
    int size, {
    int frameDurationMs = 0,
  }) async {
    final image = await StickerRenderer.renderImage(frame, size: size);
    final data = await image.toByteData(); // rawRgba (default)
    image.dispose();
    if (data == null) throw StateError('failed to rasterize a frame');
    return img.Image.fromBytes(
      width: size,
      height: size,
      bytes: data.buffer,
      numChannels: 4,
      frameDuration: frameDurationMs,
    );
  }

  /// Encodes [frames] as an animated GIF at [fps] (looping). Each frame is
  /// rendered via [StickerRenderer] then combined; GIF's 256-colour palette +
  /// 1-bit transparency are handled by the encoder. CPU-heavy — a large GIF
  /// should be offloaded to an isolate by the caller.
  static Future<EncodedSticker> gif(
    List<Frame> frames, {
    int size = 512,
    double fps = 8,
  }) async {
    assert(frames.isNotEmpty, 'need at least one frame');
    final durationMs = (1000 / fps).round().clamp(20, 10000);
    img.Image? animation;
    for (final frame in frames) {
      final frameImage = await _renderRgba(
        frame,
        size,
        frameDurationMs: durationMs,
      );
      if (animation == null) {
        animation = frameImage;
      } else {
        animation.addFrame(frameImage);
      }
    }
    return EncodedSticker(
      bytes: img.encodeGif(animation!),
      size: size,
      format: 'gif',
    );
  }

  /// Generic budget search: tries [sizes] (largest first) and returns the first
  /// whose encoded bytes are `<= maxBytes`, else the smallest tried. Pure —
  /// [encode] is injected so the search is unit-testable without real rendering.
  static Future<({Uint8List bytes, int size})> fitToBudget(
    Future<Uint8List> Function(int size) encode, {
    required int maxBytes,
    required List<int> sizes,
  }) async {
    assert(sizes.isNotEmpty, 'need at least one candidate size');
    late ({Uint8List bytes, int size}) best;
    for (final size in sizes) {
      final bytes = await encode(size);
      best = (bytes: bytes, size: size);
      if (bytes.length <= maxBytes) return best;
    }
    return best;
  }
}
