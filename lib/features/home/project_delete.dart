import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/sticker_project.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../packs/pack_repository.dart';
import '../packs/sticker_pack.dart';
import 'project_repository.dart';

/// Confirms and deletes a saved project without leaving sticker packs
/// dishonest: pack membership is looked up first so the dialog can warn
/// ('Also used in pack "X" — its slot will be removed'), and on confirm the
/// project's [PackSticker] slots are removed from every pack (persisted)
/// before the project itself is deleted — no orphan entries remain.
///
/// Shared by the Home "Recent" grid and the "All stickers" screen.
Future<void> confirmAndDeleteProject(
  BuildContext context,
  WidgetRef ref,
  StickerProject project,
) async {
  final packRepo = ref.read(packRepositoryProvider);
  var memberOf = const <StickerPack>[];
  try {
    memberOf = [
      for (final pack in await packRepo.list())
        if (pack.stickers.any((s) => s.projectId == project.id)) pack,
    ];
  } catch (_) {
    // Packs unreadable — fall back to a plain, warning-free confirm (same as
    // the historical behavior).
  }
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(
        'Delete "${project.name}"?',
        style: const TextStyle(
          fontFamily: AppFonts.display,
          color: AppColors.textPrimary,
          fontSize: 17,
        ),
      ),
      content: memberOf.isEmpty
          ? null
          : Text(
              [
                for (final pack in memberOf)
                  'Also used in pack "${pack.name}" — its slot will be '
                      'removed.',
              ].join('\n'),
              style: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: AppColors.rose)),
        ),
      ],
    ),
  );
  if (ok != true) return;

  // Cascade first so no pack ever references an already-deleted project.
  for (final pack in memberOf) {
    await packRepo.save(pack.withoutProject(project.id));
  }
  await ref.read(projectRepositoryProvider).delete(project.id);
  ref.invalidate(savedProjectsProvider);
  if (memberOf.isNotEmpty) ref.invalidate(savedPacksProvider);
}
