import 'package:flutter/widgets.dart';

/// Constrains [child] to [maxWidth] and centres it on wide screens (tablets,
/// foldables, desktop) so a phone-first layout doesn't stretch into unreadable
/// full-width rows. On a screen narrower than [maxWidth] it's a no-op — the
/// child fills the available width exactly as before. (#65)
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({super.key, required this.child, this.maxWidth = 560});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
