import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'image_adjustments.dart';
import 'layer_transform.dart';

/// A single element on a sticker: an image or a text caption. (Comic bubbles
/// arrive as a third variant in M3.) Layers are immutable; edits produce a new
/// instance via `copyWith`.
@immutable
sealed class Layer {
  const Layer({
    required this.id,
    required this.name,
    required this.transform,
    this.visible = true,
    this.opacity = 1.0,
  });

  final String id;
  final String name;
  final LayerTransform transform;
  final bool visible;

  /// 0.0 … 1.0
  final double opacity;

  /// Discriminator written into JSON.
  String get type;

  Map<String, dynamic> toJson();

  /// Base fields shared by every layer variant.
  Map<String, dynamic> baseJson() => {
    'type': type,
    'id': id,
    'name': name,
    'transform': transform.toJson(),
    'visible': visible,
    'opacity': opacity,
  };

  factory Layer.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'image' => ImageLayer.fromJson(json),
      'text' => TextLayer.fromJson(json),
      _ => throw FormatException('Unknown layer type: $type'),
    };
  }
}

/// A photo layer, optionally with an alpha mask (from AI cut-out / manual
/// erase) and per-image color adjustments.
final class ImageLayer extends Layer {
  const ImageLayer({
    required super.id,
    required super.name,
    required this.assetPath,
    super.transform = LayerTransform.identity,
    super.visible = true,
    super.opacity = 1.0,
    this.maskPath,
    this.adjustments = ImageAdjustments.identity,
  });

  /// Project-relative path to the source image.
  final String assetPath;

  /// Project-relative path to the 8-bit alpha mask, if the background has been
  /// removed or manually erased.
  final String? maskPath;

  final ImageAdjustments adjustments;

  @override
  String get type => 'image';

  ImageLayer copyWith({
    String? id,
    String? name,
    LayerTransform? transform,
    bool? visible,
    double? opacity,
    String? assetPath,
    String? maskPath,
    bool clearMask = false,
    ImageAdjustments? adjustments,
  }) {
    return ImageLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      transform: transform ?? this.transform,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      assetPath: assetPath ?? this.assetPath,
      maskPath: clearMask ? null : (maskPath ?? this.maskPath),
      adjustments: adjustments ?? this.adjustments,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'assetPath': assetPath,
    'maskPath': maskPath,
    'adjustments': adjustments.toJson(),
  };

  factory ImageLayer.fromJson(Map<String, dynamic> json) {
    return ImageLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      transform: LayerTransform.fromJson(
        (json['transform'] as Map).cast<String, dynamic>(),
      ),
      visible: json['visible'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      assetPath: json['assetPath'] as String,
      maskPath: json['maskPath'] as String?,
      adjustments: ImageAdjustments.fromJson(
        (json['adjustments'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ImageLayer &&
      other.id == id &&
      other.name == name &&
      other.transform == transform &&
      other.visible == visible &&
      other.opacity == opacity &&
      other.assetPath == assetPath &&
      other.maskPath == maskPath &&
      other.adjustments == adjustments;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    transform,
    visible,
    opacity,
    assetPath,
    maskPath,
    adjustments,
  );
}

/// A text caption layer.
final class TextLayer extends Layer {
  const TextLayer({
    required super.id,
    required super.name,
    required this.text,
    required this.fontFamily,
    super.transform = LayerTransform.identity,
    super.visible = true,
    super.opacity = 1.0,
    this.fontSize = 40,
    this.color = const Color(0xFFFFFFFF),
  });

  final String text;
  final String fontFamily;
  final double fontSize;
  final Color color;

  @override
  String get type => 'text';

  TextLayer copyWith({
    String? id,
    String? name,
    LayerTransform? transform,
    bool? visible,
    double? opacity,
    String? text,
    String? fontFamily,
    double? fontSize,
    Color? color,
  }) {
    return TextLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      transform: transform ?? this.transform,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      text: text ?? this.text,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'text': text,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'color': color.toARGB32(),
  };

  factory TextLayer.fromJson(Map<String, dynamic> json) {
    return TextLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      transform: LayerTransform.fromJson(
        (json['transform'] as Map).cast<String, dynamic>(),
      ),
      visible: json['visible'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String,
      fontFamily: json['fontFamily'] as String,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 40,
      color: Color(json['color'] as int),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextLayer &&
      other.id == id &&
      other.name == name &&
      other.transform == transform &&
      other.visible == visible &&
      other.opacity == opacity &&
      other.text == text &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.color == color;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    transform,
    visible,
    opacity,
    text,
    fontFamily,
    fontSize,
    color,
  );
}
