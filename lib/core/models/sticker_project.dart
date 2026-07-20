import 'package:flutter/foundation.dart';

import 'frame.dart';

/// The top-level editor document: a fixed-size canvas plus one or more
/// animation [frames]. Serialized as a versioned JSON manifest (see
/// [schemaVersion]); image/mask bytes live alongside it as project assets.
@immutable
class StickerProject {
  const StickerProject({
    required this.id,
    required this.name,
    required this.frames,
    this.currentFrameIndex = 0,
    this.fps = defaultFps,
    this.createdAt,
    this.updatedAt,
  });

  /// Playback / export frame rate default. Kept in sync between the editor
  /// preview and every export path so what you preview is what you get.
  static const double defaultFps = 8;

  /// Frame rate bounds. 1 fps (1 s/frame) is the slowest rate every target can
  /// actually represent: Telegram's video sticker is capped at 3 s total, so a
  /// sub-1 rate can't even fit two frames and the encode degrades into a single
  /// still that overruns the cap. The upper bound matches the messengers'
  /// 30 fps limit.
  static const double minFps = 1;
  static const double maxFps = 30;

  /// Current on-disk manifest version. Bump when the JSON shape changes and add
  /// a migration in [fromJson].
  static const int schemaVersion = 1;

  /// Logical canvas edge length, in pixels.
  static const int canvasSize = 512;

  final String id;
  final String name;
  final List<Frame> frames;
  final int currentFrameIndex;

  /// Frames per second for preview playback and animated export. Clamped to
  /// [[minFps], [maxFps]] wherever it is set.
  final double fps;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// A project with more than one frame exports as an animation.
  bool get isAnimated => frames.length > 1;

  int get frameCount => frames.length;

  /// The clamped index actually in range (defensive against bad persisted data).
  int get safeFrameIndex =>
      frames.isEmpty ? 0 : currentFrameIndex.clamp(0, frames.length - 1);

  Frame get currentFrame => frames[safeFrameIndex];

  /// Number of layers on the current frame.
  int get layerCount => frames.isEmpty ? 0 : currentFrame.layers.length;

  /// A new blank project with a single empty frame.
  factory StickerProject.empty({
    required String id,
    String name = 'Untitled',
    DateTime? createdAt,
  }) {
    return StickerProject(
      id: id,
      name: name,
      frames: [Frame(id: '${id}_f0')],
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  StickerProject copyWith({
    String? id,
    String? name,
    List<Frame>? frames,
    int? currentFrameIndex,
    double? fps,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StickerProject(
      id: id ?? this.id,
      name: name ?? this.name,
      frames: frames ?? this.frames,
      currentFrameIndex: currentFrameIndex ?? this.currentFrameIndex,
      fps: fps ?? this.fps,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'id': id,
    'name': name,
    'currentFrameIndex': currentFrameIndex,
    'fps': fps,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'frames': frames.map((f) => f.toJson()).toList(),
  };

  factory StickerProject.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    if (version > schemaVersion) {
      throw FormatException(
        'Project manifest version $version is newer than supported '
        '$schemaVersion',
      );
    }
    // Only v1 exists today; future versions add migrations before this point.
    return StickerProject(
      id: json['id'] as String,
      name: json['name'] as String,
      currentFrameIndex: json['currentFrameIndex'] as int? ?? 0,
      // Pre-fps manifests default to [defaultFps]; clamp guards bad data.
      fps: ((json['fps'] as num?)?.toDouble() ?? defaultFps).clamp(
        minFps,
        maxFps,
      ),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      frames: (json['frames'] as List)
          .map((e) => Frame.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  static DateTime? _parseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  @override
  bool operator ==(Object other) =>
      other is StickerProject &&
      other.id == id &&
      other.name == name &&
      other.currentFrameIndex == currentFrameIndex &&
      other.fps == fps &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      listEquals(other.frames, frames);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    currentFrameIndex,
    fps,
    createdAt,
    updatedAt,
    Object.hashAll(frames),
  );
}
