import 'dart:ui' show Offset;

import '../../core/models/frame.dart';
import '../../core/models/layer.dart';
import '../../core/models/layer_transform.dart';
import '../../core/models/sticker_project.dart';

/// A pre-composed sticker layout (caption placement + font + optional bubble)
/// that the "Templates" quickstart applies to a fresh (or picked-photo) canvas.
/// [buildLayers] returns the decoration layers with template-local ids; the
/// editor bumps its id counter past them on load.
class StickerTemplate {
  const StickerTemplate({
    required this.id,
    required this.name,
    required this.buildLayers,
  });

  final String id;
  final String name;
  final List<Layer> Function() buildLayers;

  /// A one-frame preview project for the picker thumbnail.
  StickerProject previewProject() => StickerProject(
    id: 'tpl_$id',
    name: name,
    frames: [Frame(id: 'tf', layers: buildLayers())],
  );
}

TextLayer _caption(
  String tid,
  String text, {
  required Offset at,
  String font = 'Bangers',
  double size = 46,
  double rotation = -0.087,
}) => TextLayer(
  id: tid,
  name: text,
  text: text,
  fontFamily: font,
  fontSize: size,
  transform: LayerTransform(position: at, rotation: rotation),
);

BubbleLayer _bubble(
  String tid,
  String text, {
  required Offset at,
  BubbleShape shape = BubbleShape.speech,
  double scale = 1,
}) => BubbleLayer(
  id: tid,
  name: text,
  text: text,
  shape: shape,
  transform: LayerTransform(position: at, scale: scale),
);

/// The curated template set surfaced by the Home "Templates" chip (≥ 6).
const List<StickerTemplate> stickerTemplates = [
  StickerTemplate(id: 'woof', name: 'Woof!', buildLayers: _woof),
  StickerTemplate(id: 'speech', name: 'Speech', buildLayers: _speech),
  StickerTemplate(id: 'thinking', name: 'Thinking', buildLayers: _thinking),
  StickerTemplate(id: 'omg', name: 'OMG', buildLayers: _omg),
  StickerTemplate(
    id: 'topbottom',
    name: 'Top & bottom',
    buildLayers: _topBottom,
  ),
  StickerTemplate(id: 'love', name: 'Love', buildLayers: _love),
  StickerTemplate(id: 'lol', name: 'LOL', buildLayers: _lol),
];

List<Layer> _woof() => [
  _caption('t0', 'WOOF!', at: const Offset(256, 400), size: 58),
];

List<Layer> _speech() => [_bubble('t0', 'Hello!', at: const Offset(256, 150))];

List<Layer> _thinking() => [
  _bubble('t0', 'Hmm…', at: const Offset(300, 150), shape: BubbleShape.thought),
];

List<Layer> _omg() => [
  _bubble('t0', 'OMG!', at: const Offset(256, 160), shape: BubbleShape.shout),
];

List<Layer> _topBottom() => [
  _caption('t0', 'WHEN', at: const Offset(256, 110), size: 40, rotation: 0),
  _caption(
    't1',
    'THE TREAT DROPS',
    at: const Offset(256, 420),
    size: 30,
    rotation: 0,
  ),
];

List<Layer> _love() => [
  _caption(
    't0',
    'love you',
    at: const Offset(256, 410),
    font: 'Pacifico',
    size: 44,
    rotation: -0.05,
  ),
];

List<Layer> _lol() => [
  _caption(
    't0',
    'LOL',
    at: const Offset(256, 400),
    font: 'LuckiestGuy',
    size: 64,
  ),
];
