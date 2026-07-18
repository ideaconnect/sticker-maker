import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/settings_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gradient_button.dart';

/// First-run intro: make → cut out → send. Three swipeable pages that explain
/// the whole flow and state the paid-premium promise (no ads, no watermarks, no
/// upsells). Completing or skipping records the flag and routes Home.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  static const _pages = <_Page>[
    _Page(
      icon: Icons.pets,
      gradient: AppColors.logoGradient,
      glow: AppColors.violetBright,
      title: 'Make it yours',
      body:
          'Start from any photo of your pet or a friend. '
          'Add text, comic bubbles, and props to make it pop.',
    ),
    _Page(
      icon: Icons.auto_fix_high,
      gradient: AppColors.cutoutGradient,
      glow: AppColors.green,
      title: 'Cut out the background',
      body:
          'One tap lifts your subject off its background — '
          'processed on your device, so your photos never leave your phone.',
    ),
    _Page(
      icon: Icons.ios_share,
      gradient: AppColors.heroGradient,
      glow: AppColors.pink,
      title: 'Send it anywhere',
      body:
          'Share to WhatsApp or Telegram, or save a transparent PNG or GIF. '
          'No ads, no watermarks, no upsells — ever.',
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ref.read(settingsStoreProvider).setOnboardingSeen(true);
    ref.invalidate(onboardingSeenProvider);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: _isLast ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: _isLast || _finishing ? null : _finish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _PageView(page: _pages[i]),
              ),
            ),
            _Dots(count: _pages.length, active: _page),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: _isLast ? 'Get started' : 'Next',
                  icon: _isLast ? Icons.check_rounded : null,
                  busy: _finishing,
                  onPressed: _next,
                  glowColor: _pages[_page].glow,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page {
  const _Page({
    required this.icon,
    required this.gradient,
    required this.glow,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final List<Color> gradient;
  final Color glow;
  final String title;
  final String body;
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: page.gradient,
              ),
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: page.glow.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Icon(page.icon, size: 58, color: Colors.white),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w700,
              fontSize: 26,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 14.5,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active ? AppColors.violetLight : AppColors.elevated,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
