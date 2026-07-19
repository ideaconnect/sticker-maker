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
      'bubble' => BubbleLayer.fromJson(json),
      _ => throw FormatException('Unknown layer type: $type'),
    };
  }
}

/// Comic speech-bubble shapes. `caption` is a tail-less rounded box for
/// narration; `whisper` is a speech bubble with a dashed outline (#80).
enum BubbleShape { speech, thought, shout, caption, whisper }

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
    this.outlineWidth = 0,
    this.outlineColor = const Color(0xFFFFFFFF),
  });

  /// Absolute path to the source image, copied into the app's assets dir by
  /// ImageImportService.
  final String assetPath;

  /// Absolute path to the 8-bit alpha mask (written by MaskStore), if the
  /// background has been removed or manually erased.
  final String? maskPath;

  final ImageAdjustments adjustments;

  /// Die-cut contour width in logical (512-canvas) pixels. `0` disables the
  /// outline. Only meaningful for a cut-out layer (one with a [maskPath]).
  final double outlineWidth;

  /// The die-cut contour color (classic sticker white by default).
  final Color outlineColor;

  /// Whether a die-cut outline is currently drawn.
  bool get hasOutline => outlineWidth > 0;

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
    double? outlineWidth,
    Color? outlineColor,
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
      outlineWidth: outlineWidth ?? this.outlineWidth,
      outlineColor: outlineColor ?? this.outlineColor,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'assetPath': assetPath,
    'maskPath': maskPath,
    'adjustments': adjustments.toJson(),
    'outlineWidth': outlineWidth,
    'outlineColor': outlineColor.toARGB32(),
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
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 0,
      outlineColor: Color(json['outlineColor'] as int? ?? 0xFFFFFFFF),
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
      other.adjustments == adjustments &&
      other.outlineWidth == outlineWidth &&
      other.outlineColor == outlineColor;

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
    outlineWidth,
    outlineColor,
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
    this.decorative = false,
  });

  final String text;
  final String fontFamily;
  final double fontSize;
  final Color color;

  /// When true this layer is a plain glyph (emoji / prop from the sticker
  /// library, #61) — rendered without the caption stroke + drop shadow so an
  /// emoji keeps its own colors.
  final bool decorative;

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
    bool? decorative,
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
      decorative: decorative ?? this.decorative,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'text': text,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'color': color.toARGB32(),
    'decorative': decorative,
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
      decorative: json['decorative'] as bool? ?? false,
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
      other.color == color &&
      other.decorative == decorative;

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
    decorative,
  );
}

/// A comic speech bubble: a vector shape (so it stays crisp at export) with an
/// optional embedded caption that reflows, a fill/stroke from the palette, and a
/// [tail] whose tip is positioned in bubble-local coordinates.
final class BubbleLayer extends Layer {
  const BubbleLayer({
    required super.id,
    required super.name,
    this.text = 'Woof!',
    this.shape = BubbleShape.speech,
    this.fontFamily = 'Bangers',
    this.fontSize = 26,
    this.fillColor = const Color(0xFFFFFFFF),
    this.strokeColor = const Color(0xFF14101A),
    this.textColor = const Color(0xFF14101A),
    this.tail = const Offset(-0.28, 0.86),
    super.transform = LayerTransform.identity,
    super.visible = true,
    super.opacity = 1.0,
  });

  final String text;
  final BubbleShape shape;
  final String fontFamily;
  final double fontSize;
  final Color fillColor;
  final Color strokeColor;
  final Color textColor;

  /// Tail tip in bubble-local normalized coordinates: the body spans roughly
  /// [-0.5, 0.5] on each axis, so a `dy > 0.5` tip points below the bubble.
  final Offset tail;

  @override
  String get type => 'bubble';

  BubbleLayer copyWith({
    String? id,
    String? name,
    LayerTransform? transform,
    bool? visible,
    double? opacity,
    String? text,
    BubbleShape? shape,
    String? fontFamily,
    double? fontSize,
    Color? fillColor,
    Color? strokeColor,
    Color? textColor,
    Offset? tail,
  }) {
    return BubbleLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      transform: transform ?? this.transform,
      visible: visible ?? this.visible,
      opacity: opacity ?? this.opacity,
      text: text ?? this.text,
      shape: shape ?? this.shape,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      textColor: textColor ?? this.textColor,
      tail: tail ?? this.tail,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson(),
    'text': text,
    'shape': shape.name,
    'fontFamily': fontFamily,
    'fontSize': fontSize,
    'fillColor': fillColor.toARGB32(),
    'strokeColor': strokeColor.toARGB32(),
    'textColor': textColor.toARGB32(),
    'tailDx': tail.dx,
    'tailDy': tail.dy,
  };

  factory BubbleLayer.fromJson(Map<String, dynamic> json) {
    return BubbleLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      transform: LayerTransform.fromJson(
        (json['transform'] as Map).cast<String, dynamic>(),
      ),
      visible: json['visible'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      text: json['text'] as String? ?? '',
      shape: BubbleShape.values.firstWhere(
        (s) => s.name == json['shape'],
        orElse: () => BubbleShape.speech,
      ),
      fontFamily: json['fontFamily'] as String? ?? 'Bangers',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 26,
      fillColor: Color(json['fillColor'] as int? ?? 0xFFFFFFFF),
      strokeColor: Color(json['strokeColor'] as int? ?? 0xFF14101A),
      textColor: Color(json['textColor'] as int? ?? 0xFF14101A),
      tail: Offset(
        (json['tailDx'] as num?)?.toDouble() ?? -0.28,
        (json['tailDy'] as num?)?.toDouble() ?? 0.86,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BubbleLayer &&
      other.id == id &&
      other.name == name &&
      other.transform == transform &&
      other.visible == visible &&
      other.opacity == opacity &&
      other.text == text &&
      other.shape == shape &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fillColor == fillColor &&
      other.strokeColor == strokeColor &&
      other.textColor == textColor &&
      other.tail == tail;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    transform,
    visible,
    opacity,
    text,
    shape,
    fontFamily,
    fontSize,
    fillColor,
    strokeColor,
    textColor,
    tail,
  );
}
