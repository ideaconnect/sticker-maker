import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Prompts for a name (e.g. renaming a sticker project). Returns the trimmed
/// name, or null if cancelled / left blank — blank input never renames, so
/// callers keep the old name (mirrors the pack rename guard).
Future<String?> promptName(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = 'Name',
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _NamePromptDialog(
      title: title,
      initial: initial,
      hint: hint,
      confirmLabel: confirmLabel,
    ),
  ).then((v) {
    final name = v?.trim() ?? '';
    return name.isEmpty ? null : name;
  });
}

/// Owns its [TextEditingController] so it is disposed exactly when the dialog
/// element leaves the tree — disposing an externally-held controller right
/// after `showDialog` returns crashes the dialog's exit animation.
class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String hint;
  final String confirmLabel;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
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
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(
        widget.title,
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
          hintText: widget.hint,
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
        TextButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
