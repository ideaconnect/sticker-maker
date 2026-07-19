import 'package:flutter/material.dart';

/// The app's brand mark (the icon tile artwork), for in-app lockups.
///
/// The artwork is itself a pre-rounded gradient tile, so it is drawn directly
/// rather than inside another gradient chip. [radius] only clips — it never
/// draws a fill — and is kept slightly wider than the artwork's own corners so
/// the two never fight; [shadow] carries the surrounding chip's depth.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    required this.size,
    required this.radius,
    this.shadow = const <BoxShadow>[],
  });

  final double size;
  final double radius;
  final List<BoxShadow> shadow;

  static const String assetPath = 'assets/branding/logo.png';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Sticker Maker logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: shadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
