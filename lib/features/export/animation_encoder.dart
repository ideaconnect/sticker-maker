import 'dart:typed_data';

/// Per-target constraints for an animated sticker. Enforced in pure Dart around
/// the native encode (see docs/decisions/0002-animated-encoders.md).
class AnimationSpec {
  const AnimationSpec({
    required this.format,
    required this.maxBytes,
    this.maxEdge = 512,
    this.maxFps = 30,
    this.maxSeconds,
    this.minFrameMs = 0,
    this.loop = true,
  });

  /// `webp` (WhatsApp) or `webm` (Telegram VP9).
  final String format;
  final int maxBytes;
  final int maxEdge;
  final double maxFps;
  final double? maxSeconds;
  final int minFrameMs;
  final bool loop;

  /// WhatsApp animated sticker: 512², ≤ 500 KB, ≤ 10 s, frames ≥ 8 ms.
  static const whatsappWebp = AnimationSpec(
    format: 'webp',
    maxBytes: 500 * 1024,
    maxSeconds: 10,
    minFrameMs: 8,
  );

  /// Telegram video sticker: 512², ≤ 256 KB, ≤ 3 s, ≤ 30 fps, no audio, VP9.
  static const telegramWebm = AnimationSpec(
    format: 'webm',
    maxBytes: 256 * 1024,
    maxSeconds: 3,
  );
}

/// One rendered frame handed to the encoder: straight-alpha RGBA bytes
/// (`width*height*4`) plus how long it shows.
class RgbaFrame {
  const RgbaFrame({
    required this.bytes,
    required this.width,
    required this.height,
    required this.durationMs,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int durationMs;
}

/// Which source frames to keep and how long each shows, after applying an
/// [AnimationSpec]'s fps / duration / min-frame caps. Pure planning — the input
/// to the (device) native encoders.
class FramePlan {
  const FramePlan({required this.frameIndices, required this.frameDurationMs});

  final List<int> frameIndices;
  final int frameDurationMs;

  int get frameCount => frameIndices.length;
  double get totalSeconds => frameCount * frameDurationMs / 1000;
}

/// Pure frame-timing planner: caps fps, clamps the per-frame duration to the
/// spec's minimum, and truncates to the max duration by keeping the leading
/// frames. Host-unit-testable; no rendering or native code.
abstract final class AnimationPlanner {
  AnimationPlanner._();

  /// Slowest allowed rate: 0.25 fps = 4 s/frame, matching the editor's
  /// slow-motion presets. (Duration caps below may still drop frames.)
  static const double minFps = 0.25;

  static FramePlan plan(int frameCount, double fps, AnimationSpec spec) {
    assert(frameCount > 0, 'need at least one frame');
    final effectiveFps = fps.clamp(minFps, spec.maxFps);
    final durationMs = (1000 / effectiveFps).round().clamp(
      spec.minFrameMs == 0 ? 1 : spec.minFrameMs,
      10000,
    );
    var count = frameCount;
    final maxSeconds = spec.maxSeconds;
    if (maxSeconds != null) {
      final maxFrames = (maxSeconds * 1000 / durationMs).floor().clamp(
        1,
        frameCount,
      );
      if (maxFrames < count) count = maxFrames;
    }
    return FramePlan(
      frameIndices: [for (var i = 0; i < count; i++) i],
      frameDurationMs: durationMs,
    );
  }
}

/// The single native seam for animated encoding. Implementations
/// (`LibWebpAnimationEncoder`, `Vp9WebmEncoder`) are device-only (dart:ffi);
/// tests inject [FakeAnimationEncoder]. Mirrors `SegmentationEngine`.
abstract interface class AnimationEncoder {
  String get id;
  String get format;

  /// Whether the native encoder is usable on this device right now. Must not
  /// throw — returns false on any uncertainty (so the export UI can degrade
  /// gracefully until the native library ships).
  Future<bool> isAvailable();

  /// Encodes [frames] at [quality] (0…100 for WebP; a bitrate/CQ knob for VP9).
  Future<Uint8List> encode(
    List<RgbaFrame> frames, {
    required int quality,
    required bool loop,
  });

  /// Prepares [frames] once for repeated [AnimationEncodeSession.encode] calls
  /// at different qualities (the byte-budget search): the expensive per-frame
  /// preprocessing (e.g. the ffmpeg PNG scratch sequence) happens here, not per
  /// rung. Callers own the session and must [AnimationEncodeSession.dispose].
  Future<AnimationEncodeSession> prepare(List<RgbaFrame> frames);
}

/// A prepared set of frames that can be encoded at many qualities. Obtained
/// from [AnimationEncoder.prepare]; each [encode] re-runs only the codec pass.
abstract interface class AnimationEncodeSession {
  /// Encodes the prepared frames at [quality] (same knob as
  /// [AnimationEncoder.encode]).
  Future<Uint8List> encode({required int quality, required bool loop});

  /// Releases scratch resources (temp dirs, native handles). Safe to call more
  /// than once; the session is unusable afterwards.
  Future<void> dispose();
}

/// An encoded animation plus the quality-knob value that produced it.
class BudgetedEncode {
  const BudgetedEncode({
    required this.bytes,
    required this.quality,
    required this.withinBudget,
  });

  final Uint8List bytes;
  final int quality;

  /// False when even the lowest-quality rung exceeded the byte cap — the caller
  /// gets the best effort and decides whether to refuse the export.
  final bool withinBudget;
}

/// Byte-budget search over an [AnimationEncoder]'s quality knob: tries
/// [qualities] (best first) and returns the first encode within
/// [spec].maxBytes, else the last (smallest) attempt flagged out-of-budget.
///
/// The frames are [AnimationEncoder.prepare]d ONCE for the whole search — the
/// per-frame preprocessing is identical across rungs, so only the codec pass
/// re-runs per quality.
///
/// Both platforms pin the 512-px edge exactly, so unlike the static-sticker
/// budget search this NEVER downscales — quality/bitrate is the only variable.
Future<BudgetedEncode> encodeWithinBudget(
  AnimationEncoder encoder,
  List<RgbaFrame> frames,
  AnimationSpec spec, {
  required List<int> qualities,
}) async {
  assert(qualities.isNotEmpty, 'need at least one quality rung');
  final session = await encoder.prepare(frames);
  try {
    late Uint8List last;
    late int lastQuality;
    for (final quality in qualities) {
      last = await session.encode(quality: quality, loop: spec.loop);
      lastQuality = quality;
      if (last.length <= spec.maxBytes) {
        return BudgetedEncode(
          bytes: last,
          quality: quality,
          withinBudget: true,
        );
      }
    }
    return BudgetedEncode(
      bytes: last,
      quality: lastQuality,
      withinBudget: false,
    );
  } finally {
    await session.dispose();
  }
}

/// Quality ladders per target (best first). Telegram's knob is VP9 bitrate in
/// kbps; WhatsApp's is libwebp 0–100 quality.
///
/// The Telegram ladder is **duration-aware**: a fixed low bitrate wastes the
/// 256 KB budget on short clips (a 1 s clip can afford ~1800 kbps) and produces
/// blocky chroma garbage around cut-out edges. [telegramBitrateLadderFor]
/// derives the top rung from the actual clip length and descends from there.
List<int> telegramBitrateLadderFor(
  double durationSeconds, {
  int maxBytes = 256 * 1024,
}) {
  final seconds = durationSeconds.clamp(0.1, 10.0);
  // 90% of the byte budget as bits/s, clamped to sane VP9 territory.
  final target = (maxBytes * 8 * 0.90 / 1000 / seconds).round().clamp(
    200,
    4000,
  );
  return [
    for (final f in const [1.0, 0.75, 0.55, 0.4, 0.28, 0.18, 0.1])
      (target * f).round().clamp(64, 4000),
  ];
}

const whatsappQualityLadder = <int>[80, 70, 60, 50, 40, 30];

/// Test double: records the last call and returns canned bytes whose length is
/// `frameCount * quality` so byte-budget searches are deterministic. Counts
/// [prepare]/session activity so tests can prove frames are prepared once.
class FakeAnimationEncoder implements AnimationEncoder {
  FakeAnimationEncoder({
    this.id = 'fake',
    this.format = 'webp',
    this.available = true,
  });

  @override
  final String id;
  @override
  final String format;
  final bool available;

  int? lastQuality;
  int? lastFrameCount;
  int prepareCalls = 0;
  int sessionEncodeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Uint8List> encode(
    List<RgbaFrame> frames, {
    required int quality,
    required bool loop,
  }) async {
    lastQuality = quality;
    lastFrameCount = frames.length;
    return Uint8List(frames.length * quality);
  }

  @override
  Future<AnimationEncodeSession> prepare(List<RgbaFrame> frames) async {
    prepareCalls++;
    return _FakeAnimationEncodeSession(this, frames);
  }
}

class _FakeAnimationEncodeSession implements AnimationEncodeSession {
  _FakeAnimationEncodeSession(this._encoder, this._frames);

  final FakeAnimationEncoder _encoder;
  final List<RgbaFrame> _frames;

  @override
  Future<Uint8List> encode({required int quality, required bool loop}) {
    _encoder.sessionEncodeCalls++;
    return _encoder.encode(_frames, quality: quality, loop: loop);
  }

  @override
  Future<void> dispose() async {
    _encoder.disposeCalls++;
  }
}
