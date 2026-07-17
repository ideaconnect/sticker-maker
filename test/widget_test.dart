import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/app/app.dart';

void main() {
  // Exercise layout at the design's target phone size (412 x 892 @ 2x).
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(824, 1784);
    view.devicePixelRatio = 2.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('Home screen renders brand and primary action', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: StickerMakerApp()));
    await tester.pumpAndSettle();

    expect(find.text('Sticker Maker'), findsOneWidget);
    expect(find.text('New Sticker'), findsOneWidget);
    expect(find.text('Recent stickers'), findsOneWidget);
  });

  testWidgets('New Sticker navigates to the editor', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: StickerMakerApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Sticker'));
    await tester.pumpAndSettle();

    expect(find.text('Rex woof'), findsOneWidget);
    expect(find.text('Cut out'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('Editor Export button navigates to the export screen', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: StickerMakerApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Sticker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    expect(find.text('Export sticker'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });

  testWidgets('Editor back button pops to Home (real back stack)', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: StickerMakerApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Sticker'));
    await tester.pumpAndSettle();
    // Editor-only subtitle confirms we're on the editor.
    expect(find.text('512 × 512 · transparent'), findsOneWidget);

    // The chevron back must pop (not replace) so Android system back works too.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(find.text('New Sticker'), findsOneWidget);
    expect(find.text('512 × 512 · transparent'), findsNothing);
  });
}
