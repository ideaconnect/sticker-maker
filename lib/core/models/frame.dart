import 'package:flutter/foundation.dart';

import 'layer.dart';

/// One animation frame: an ordered list of [Layer]s (bottom-to-top z-order).
/// A static sticker is a project with a single frame.
@immutable
class Frame {
  const Frame({required this.id, this.layers = const []});

  final String id;
  final List<Layer> layers;

  Frame copyWith({String? id, List<Layer>? layers}) {
    return Frame(id: id ?? this.id, layers: layers ?? this.layers);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'layers': layers.map((l) => l.toJson()).toList(),
  };

  factory Frame.fromJson(Map<String, dynamic> json) {
    return Frame(
      id: json['id'] as String,
      layers: (json['layers'] as List)
          .map((e) => Layer.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Frame && other.id == id && listEquals(other.layers, layers);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(layers));
}
