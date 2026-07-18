import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Parses a free-text emoji field into at most [max] emoji tags. Splits on
/// grapheme clusters (so multi-codepoint emoji stay whole) and drops
/// whitespace. Pure — unit-tested directly.
List<String> parseEmojiTags(String input, {int max = 3}) {
  return input.characters
      .where((c) => c.trim().isNotEmpty)
      .take(max)
      .toList(growable: false);
}

/// Prompts for a pack name (create or rename). Returns the trimmed name, or
/// null if cancelled / left blank. [initial] pre-fills for a rename.
Future<String?> promptPackName(BuildContext context, {String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _NameDialog(initial: initial),
  ).then((v) {
    final name = v?.trim() ?? '';
    return name.isEmpty ? null : name;
  });
}

/// Emoji-tag editor for one sticker. Returns the parsed 1–3 tags, or null if
/// cancelled.
Future<List<String>?> promptEmojis(
  BuildContext context, {
  List<String> initial = const [],
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => _EmojiDialog(initial: initial),
  );
}

/// Owns its [TextEditingController] so it is disposed exactly when the dialog
/// element leaves the tree — disposing an externally-held controller right
/// after `showDialog` returns crashes the dialog's exit animation.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final creating = widget.initial.isEmpty;
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(
        creating ? 'New pack' : 'Rename pack',
        style: const TextStyle(
          fontFamily: AppFonts.display,
          color: AppColors.textPrimary,
          fontSize: 17,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.inputField,
          hintText: 'Pack name',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(creating ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

class _EmojiDialog extends StatefulWidget {
  const _EmojiDialog({required this.initial});

  final List<String> initial;

  @override
  State<_EmojiDialog> createState() => _EmojiDialogState();
}

class _EmojiDialogState extends State<_EmojiDialog> {
  static const _quick = [
    '😀',
    '❤️',
    '😂',
    '🔥',
    '👍',
    '🐶',
    '🐱',
    '🎉',
    '😎',
    '🙌',
  ];

  late final TextEditingController _controller = TextEditingController(
    text: widget.initial.join(' '),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String emoji) {
    setState(() {
      _controller.text = parseEmojiTags('${_controller.text}$emoji').join(' ');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text(
        'Emoji tags',
        style: TextStyle(
          fontFamily: AppFonts.display,
          color: AppColors.textPrimary,
          fontSize: 17,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WhatsApp suggests stickers by emoji. Add 1–3.',
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 12.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 20),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.inputField,
              hintText: '😀 🐶 🎉',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _quick)
                GestureDetector(
                  onTap: () => _add(e),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.chipSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 20)),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, parseEmojiTags(_controller.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
