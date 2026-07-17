import 'package:flutter/foundation.dart';

/// Per-image color adjustments driven by the Adjust tool. Multiplicative
/// factors are expressed as `1.0 == 100%` (matching the design's sliders);
/// [hue] is a rotation in degrees (−180…180).
@immutable
class ImageAdjustments {
  const ImageAdjustments({
    this.brightness = 1.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.hue = 0.0,
  });

  final double brightness;
  final double contrast;
  final double saturation;
  final double hue;

  static const ImageAdjustments identity = ImageAdjustments();

  bool get isIdentity => this == identity;

  ImageAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? hue,
  }) {
    return ImageAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      hue: hue ?? this.hue,
    );
  }

  Map<String, dynamic> toJson() => {
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'hue': hue,
  };

  factory ImageAdjustments.fromJson(Map<String, dynamic> json) {
    return ImageAdjustments(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 1.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
      hue: (json['hue'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ImageAdjustments &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.hue == hue;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation, hue);
}
