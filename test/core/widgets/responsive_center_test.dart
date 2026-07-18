import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/widgets/responsive_center.dart';

/// Lays out a full-width child inside a [ResponsiveCenter] within [available]
/// logical pixels and returns the child's rendered width.
Future<double> _childWidth(WidgetTester tester, double available) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: available,
          height: 100,
          child: ResponsiveCenter(
            child: SizedBox(key: key, width: double.infinity, height: 10),
          ),
        ),
      ),
    ),
  );
  return tester.getSize(find.byKey(key)).width;
}

void main() {
  testWidgets('constrains content to maxWidth on a wide screen', (
    tester,
  ) async {
    // 760 px available (> 560 default) → child is capped at 560.
    expect(await _childWidth(tester, 760), 560);
  });

  testWidgets('fills the width on a narrow (phone) screen', (tester) async {
    // 320 px available (< 560) → no-op, child fills the width.
    expect(await _childWidth(tester, 320), 320);
  });

  testWidgets('honours a custom maxWidth', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 760,
            height: 100,
            child: ResponsiveCenter(
              maxWidth: 400,
              child: SizedBox(key: key, width: double.infinity, height: 10),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(key)).width, 400);
  });
}
