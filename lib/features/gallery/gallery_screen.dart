import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sm_tokens.dart';
import '../../core/widgets/checkerboard.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/labeled_slider.dart';
import '../../core/widgets/pill_chip.dart';
import '../../core/widgets/sm_toast.dart';
import '../../core/widgets/sticker_caption.dart';
import '../../core/widgets/tool_tab.dart';

/// A developer-facing gallery of the shared design-system widgets, used to
/// eyeball fidelity against `design/Sticker Maker.dc.html` and as the visual
/// target for golden tests. Reachable at `/gallery`.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  double _slider = 118;
  bool _pillSelected = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Design system')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section('Gradient buttons'),
          GradientButton(
            label: 'New Sticker',
            icon: Icons.add,
            onPressed: () {},
          ),
          const SizedBox(height: 10),
          GradientButton(
            label: 'Remove background',
            icon: Icons.auto_awesome,
            gradient: context.sm.cutoutGradient,
            glowColor: AppColors.green,
            onPressed: () {},
          ),
          const SizedBox(height: 10),
          GradientButton(
            label: 'Undo removal',
            icon: Icons.auto_awesome,
            solidColor: AppColors.neutralButton,
            foreground: AppColors.textSecondary,
            onPressed: () {},
          ),
          const SizedBox(height: 10),
          const GradientButton(label: 'Disabled'),
          _section('Sticker caption'),
          const SizedBox(
            height: 70,
            child: ColoredBox(
              color: AppColors.cardAlt,
              child: Center(
                child: StickerCaption(
                  text: 'WOOF!',
                  fontFamily: AppFonts.bangers,
                  fontSize: 34,
                ),
              ),
            ),
          ),
          _section('Tool tabs'),
          DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF141019)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  ToolTab(
                    label: 'Layers',
                    icon: Icons.layers_outlined,
                    accent: AppColors.violet,
                    active: true,
                    onTap: () {},
                  ),
                  ToolTab(
                    label: 'Adjust',
                    icon: Icons.tune,
                    accent: AppColors.cyan,
                    active: false,
                    onTap: () {},
                  ),
                  ToolTab(
                    label: 'Text',
                    icon: Icons.text_fields,
                    accent: AppColors.pink,
                    active: false,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
          _section('Labeled slider'),
          LabeledSlider(
            label: 'Saturation',
            value: _slider,
            min: 0,
            max: 200,
            accent: AppColors.pink,
            valueLabel: '${_slider.round()}%',
            onChanged: (v) => setState(() => _slider = v),
          ),
          _section('Pill chips'),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              PillChip(label: 'Reset', onTap: () {}),
              PillChip(label: 'Add', icon: Icons.add, onTap: () {}),
              PillChip(
                label: 'Selected',
                accent: AppColors.pink,
                selected: _pillSelected,
                onTap: () => setState(() => _pillSelected = !_pillSelected),
              ),
            ],
          ),
          _section('Sticker fonts'),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final f in AppFonts.stickerFonts)
                Text(
                  'Woof!',
                  style: TextStyle(
                    fontFamily: f,
                    fontSize: 24,
                    color: AppColors.textPrimary,
                  ),
                ),
            ],
          ),
          _section('Checkerboard'),
          SizedBox(
            height: 90,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: const Checkerboard(),
            ),
          ),
          _section('Toast'),
          PillChip(
            label: 'Show toast',
            icon: Icons.notifications_none,
            onTap: () => showSmToast(context, 'Sticker exported'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
  );
}
