import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/checkerboard.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/sm_toast.dart';
import '../../core/widgets/sticker_caption.dart';

/// Export screen: preview, static/animated toggle, target picker, and the
/// export action. Encoders arrive in milestone M5 — this is the shell.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _animated = true;
  String _target = 'telegram';
  bool _exporting = false;

  static const _targets = <_Target>[
    _Target(
      'telegram',
      'Telegram',
      'Static + video sticker',
      AppColors.cyan,
      'T',
    ),
    _Target(
      'whatsapp',
      'WhatsApp',
      'Sticker pack (.webp)',
      AppColors.green,
      'W',
    ),
    _Target('png', 'PNG', 'Transparent image', AppColors.violet, 'P'),
    _Target('webp', 'WebP', 'Smaller file size', AppColors.pink, 'WP'),
    _Target('gif', 'GIF', 'Animated, shareable', AppColors.amber, 'G'),
  ];

  static const _dims = {
    'telegram': '512 × 512 px',
    'whatsapp': '512 × 512 px',
    'png': '1024 × 1024 px',
    'webp': '512 × 512 px',
    'gif': '512 × 512 px',
  };

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() => _exporting = false);
    showSmToast(context, 'Export pipeline arrives in M5');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  _preview(),
                  const SizedBox(height: 18),
                  _modeToggle(),
                  const SizedBox(height: 20),
                  const Text(
                    'SEND TO',
                    style: TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final t in _targets) ...[
                    _targetCard(t),
                    const SizedBox(height: 9),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _dims[_target]!,
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        _animated ? '~64 KB · WebM/GIF' : '~18 KB · PNG',
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GradientButton(
                    label: _exporting
                        ? 'Exporting…'
                        : 'Export ${_animated ? 'animation' : 'sticker'}',
                    icon: _exporting ? null : Icons.ios_share,
                    busy: _exporting,
                    onPressed: _export,
                    padding: const EdgeInsets.all(16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(
              Icons.chevron_left,
              size: 26,
              color: AppColors.textSecondary,
            ),
          ),
          const Expanded(
            child: Text(
              'Export sticker',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: () => context.goNamed(Routes.home),
            icon: const Icon(Icons.close, size: 22, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    return Center(
      child: SizedBox(
        width: 170,
        height: 170,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: const Stack(
              fit: StackFit.expand,
              children: [
                Checkerboard(cell: 11),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 22,
                  child: Center(
                    child: StickerCaption(
                      text: 'WOOF!',
                      fontFamily: AppFonts.bangers,
                      fontSize: 26,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeTab(
              'Static',
              Icons.image_outlined,
              !_animated,
              () => setState(() => _animated = false),
            ),
          ),
          Expanded(
            child: _modeTab(
              'Animated',
              Icons.gif_box_outlined,
              _animated,
              () => setState(() => _animated = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab(
    String label,
    IconData icon,
    bool active,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? AppColors.elevated : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? Colors.white : AppColors.textMuted,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetCard(_Target t) {
    final selected = _target == t.id;
    return GestureDetector(
      onTap: () => setState(() => _target = t.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? t.color.withValues(alpha: 0.10) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? t.color.withValues(alpha: 0.6)
                : AppColors.borderFaint,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                t.abbr,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: t.color,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name,
                    style: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    t.sub,
                    style: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? t.color : Colors.transparent,
                border: selected
                    ? null
                    : Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 2,
                      ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Target {
  const _Target(this.id, this.name, this.sub, this.color, this.abbr);
  final String id;
  final String name;
  final String sub;
  final Color color;
  final String abbr;
}
