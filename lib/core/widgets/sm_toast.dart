import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// The currently-visible toast, if any. A new toast replaces it so rapid
/// triggers (Undo/Redo/Reset) never stack overlapping pills.
OverlayEntry? _activeToast;

/// Shows a transient confirmation toast pinned near the bottom of the screen,
/// matching the design's pill toast with a green status dot and pop-in.
void showSmToast(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);
  _activeToast?.remove();
  _activeToast = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SmToast(
      message: message,
      onDismissed: () {
        if (identical(_activeToast, entry)) _activeToast = null;
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

class _SmToast extends StatefulWidget {
  const _SmToast({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_SmToast> createState() => _SmToastState();
}

class _SmToastState extends State<_SmToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _hold = Timer(
      const Duration(milliseconds: 1500),
      () => unawaited(_dismiss()),
    );
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _c.reverse().orCancel.catchError((_) {});
    if (!mounted) return;
    widget.onDismissed();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _curved.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 40,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.4),
                end: Offset.zero,
              ).animate(_curved),
              child: _ToastPill(message: widget.message),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastPill extends StatelessWidget {
  const _ToastPill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.chipSurface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              message,
              style: const TextStyle(
                fontFamily: AppFonts.ui,
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
