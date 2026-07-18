import 'dart:typed_data';

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

/// Static sticker encoders. PNG is native (transparent); the budget search
/// downscales until the output fits a per-target byte cap (WhatsApp static
/// ≤ 100 KB, etc.). Animated encoders (GIF #40, WebP/WebM #41/#42) build on the
/// same [StickerRenderer].
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
