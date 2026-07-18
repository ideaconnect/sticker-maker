import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// The curated emoji/prop library shown in the picker (#61). A flat, ordered
/// set spanning faces, animals, hearts/symbols, and hands/party — enough
/// variety to decorate a sticker without overwhelming the grid.
const kStickerEmojis = <String>[
  // Faces
  '😀', '😂', '😍', '😎', '🥳', '😭', '😡', '🤔', '😴', '🤯', '🥰', '😇',
  // Animals
  '🐶', '🐱', '🐭', '🦊', '🐻', '🐼', '🐨', '🐸', '🐵', '🦁', '🐷', '🐰',
  // Hearts & symbols
  '❤️', '🧡', '💛', '💚', '💙', '💜', '⭐', '✨', '🔥', '💯', '🎉', '🎈',
  // Hands & gestures
  '👍', '👎', '🙌', '👏', '🙏', '💪', '🤝', '👋', '🤟', '✌️', '🤙', '🫶',
];

/// Presents the emoji library. Returns the chosen emoji, or null if dismissed.
Future<String?> showEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => const _EmojiPickerSheet(),
  );
}

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.elevated,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Add a sticker',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap to drop it on the canvas — then resize and rotate.',
              style: TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: GridView.count(
                crossAxisCount: 6,
                shrinkWrap: true,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final emoji in kStickerEmojis)
                    _EmojiTile(
                      emoji: emoji,
                      onTap: () => Navigator.pop(context, emoji),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}
