import 'package:flutter/foundation.dart';

import '../export/compliance_validator.dart';

/// One sticker slot in a [StickerPack]: a reference to a saved project plus its
/// WhatsApp emoji tags (1–3).
@immutable
class PackSticker {
  const PackSticker({
    required this.id,
    required this.projectId,
    this.emojis = const [],
  });

  final String id;
  final String projectId;
  final List<String> emojis;

  PackSticker copyWith({String? id, String? projectId, List<String>? emojis}) =>
      PackSticker(
        id: id ?? this.id,
        projectId: projectId ?? this.projectId,
        emojis: emojis ?? this.emojis,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'emojis': emojis,
  };

  factory PackSticker.fromJson(Map<String, dynamic> json) => PackSticker(
    id: json['id'] as String,
    projectId: json['projectId'] as String,
    emojis: ((json['emojis'] as List?) ?? const []).cast<String>(),
  );

  @override
  bool operator ==(Object other) =>
      other is PackSticker &&
      other.id == id &&
      other.projectId == projectId &&
      listEquals(other.emojis, emojis);

  @override
  int get hashCode => Object.hash(id, projectId, Object.hashAll(emojis));
}

/// A local sticker pack: a named, single-publisher collection of 3–30 stickers
/// that are **all static or all animated** (never mixed). Serialized as JSON;
/// the tray icon is generated from the first sticker at build/share time.
@immutable
class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    this.publisher = 'Sticker Maker',
    this.animated = false,
    this.stickers = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String publisher;

  /// Whether this pack holds animated stickers (all of them) or static ones.
  final bool animated;
  final List<PackSticker> stickers;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get count => stickers.length;
  bool get isEmpty => stickers.isEmpty;

  StickerPack copyWith({
    String? id,
    String? name,
    String? publisher,
    bool? animated,
    List<PackSticker>? stickers,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => StickerPack(
    id: id ?? this.id,
    name: name ?? this.name,
    publisher: publisher ?? this.publisher,
    animated: animated ?? this.animated,
    stickers: stickers ?? this.stickers,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Appends [sticker] (no-op if its project is already in the pack).
  StickerPack withSticker(PackSticker sticker) {
    if (stickers.any((s) => s.projectId == sticker.projectId)) return this;
    return copyWith(stickers: [...stickers, sticker]);
  }

  StickerPack withoutSticker(String stickerId) =>
      copyWith(stickers: stickers.where((s) => s.id != stickerId).toList());

  /// Removes every slot that references [projectId] (used when the source
  /// project is deleted, so packs never keep dangling references).
  StickerPack withoutProject(String projectId) => copyWith(
    stickers: stickers.where((s) => s.projectId != projectId).toList(),
  );

  StickerPack reorder(int oldIndex, int newIndex) {
    final next = [...stickers];
    final item = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), item);
    return copyWith(stickers: next);
  }

  StickerPack setEmojis(String stickerId, List<String> emojis) => copyWith(
    stickers: [
      for (final s in stickers)
        if (s.id == stickerId) s.copyWith(emojis: emojis) else s,
    ],
  );

  /// Model-level compliance issues (pack size, and — for WhatsApp — that every
  /// sticker carries 1–3 emoji tags). Byte/dimension checks happen at encode
  /// time via [ComplianceValidator.validateSticker].
  ///
  /// Pass [knownProjectIds] (the ids of every saved project) to also flag
  /// stickers whose source project no longer exists — an error, because the
  /// exporters would silently skip them and ship a short pack. When it is
  /// null (caller can't resolve projects yet), that check is skipped and the
  /// result matches the historical no-arg behavior.
  List<ComplianceIssue> validate({
    StickerTarget target = StickerTarget.whatsapp,
    Set<String>? knownProjectIds,
  }) {
    final issues = ComplianceValidator.validatePack(
      stickerCount: count,
      hasStatic: !animated,
      hasAnimated: animated,
      target: target,
    );
    if (knownProjectIds != null) {
      final missing = missingProjectCount(knownProjectIds);
      if (missing > 0) {
        issues.add(
          ComplianceIssue(
            missing == 1
                ? '1 sticker is missing its source project — remove its slot '
                      'or recreate the sticker.'
                : '$missing stickers are missing their source project — '
                      'remove their slots or recreate the stickers.',
          ),
        );
      }
    }
    if (target == StickerTarget.whatsapp) {
      final untagged = stickers
          .where((s) => s.emojis.isEmpty || s.emojis.length > 3)
          .length;
      if (untagged > 0) {
        issues.add(
          ComplianceIssue(
            '$untagged sticker${untagged == 1 ? '' : 's'} need 1–3 emoji tags.',
          ),
        );
      }
    }
    return issues;
  }

  /// How many stickers reference a project that is not in [knownProjectIds].
  int missingProjectCount(Set<String> knownProjectIds) =>
      stickers.where((s) => !knownProjectIds.contains(s.projectId)).length;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'publisher': publisher,
    'animated': animated,
    'stickers': [for (final s in stickers) s.toJson()],
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory StickerPack.fromJson(Map<String, dynamic> json) => StickerPack(
    id: json['id'] as String,
    name: json['name'] as String,
    publisher: json['publisher'] as String? ?? 'Sticker Maker',
    animated: json['animated'] as bool? ?? false,
    stickers: ((json['stickers'] as List?) ?? const [])
        .map((e) => PackSticker.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}
