import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Position / scale / rotation of a layer within the 512×512 logical canvas.
/// [position] is the layer's center, in logical canvas units.
@immutable
class LayerTransform {
  const LayerTransform({
    this.position = const Offset(256, 256),
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  final Offset position;
  final double scale;

  /// Rotation in radians.
  final double rotation;

  static const LayerTransform identity = LayerTransform();

  LayerTransform copyWith({Offset? position, double? scale, double? rotation}) {
    return LayerTransform(
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() => {
    'x': position.dx,
    'y': position.dy,
    'scale': scale,
    'rotation': rotation,
  };

  factory LayerTransform.fromJson(Map<String, dynamic> json) {
    return LayerTransform(
      position: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      scale: (json['scale'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LayerTransform &&
      other.position == position &&
      other.scale == scale &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(position, scale, rotation);
}
