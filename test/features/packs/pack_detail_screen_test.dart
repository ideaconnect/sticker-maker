import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/home/project_repository.dart';
import 'package:sticker_maker/features/packs/pack_detail_screen.dart';
import 'package:sticker_maker/features/packs/pack_repository.dart';
import 'package:sticker_maker/features/packs/sticker_pack.dart';
import 'package:sticker_maker/features/packs/telegram_pack_exporter.dart';
import 'package:sticker_maker/features/packs/telegram_pack_share.dart';
import 'package:sticker_maker/features/packs/whatsapp_pack_installer.dart';

/// In-memory repository so widget-test fake-async isn't blocked on real file IO.
class _FakePackRepository extends PackRepository {
  _FakePackRepository(List<StickerPack> initial) {
    for (final p in initial) {
      _store[p.id] = p;
    }
  }

  final Map<String, StickerPack> _store = {};

  @override
  Future<void> save(StickerPack pack) async => _store[pack.id] = pack;
  @override
  Future<List<StickerPack>> list() async => _store.values.toList();
  @override
  Future<StickerPack?> load(String id) async => _store[id];
  @override
  Future<void> delete(String id) async => _store.remove(id);
}

StickerProject _project(String id, String name) => StickerProject(
  id: id,
  name: name,
  frames: [Frame(id: '${id}_f0')],
);

PackSticker _sticker(String projectId, {List<String> emojis = const []}) =>
    PackSticker(id: 'ps_$projectId', projectId: projectId, emojis: emojis);

final _projects = [
  _project('p_rex', 'Rex'),
  _project('p_bella', 'Bella'),
  _project('p_charlie', 'Charlie'),
];

/// A 2-sticker static pack: Rex is tagged, Bella is not. (< 3 → "Not ready".)
StickerPack _seedPack() => StickerPack(
  id: 'pack1',
  name: 'Doggos',
  stickers: [
    _sticker('p_rex', emojis: const ['🐶']),
    _sticker('p_bella'),
  ],
);

Future<_FakePackRepository> _pumpDetail(WidgetTester tester) async {
  final repo = _FakePackRepository([_seedPack()]);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/pack/pack1'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/pack/:id',
        builder: (context, state) =>
            PackDetailScreen(packId: state.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        packRepositoryProvider.overrideWithValue(repo),
        savedProjectsProvider.overrideWith((ref) => _projects),
      ],
      child: MaterialApp.router(
        theme: buildStickerTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

/// A fully WhatsApp-compliant static pack: 3 stickers, each with 1–3 emoji
/// tags, all resolving to a saved project — so `validate()` returns no issues
/// and the compliance-gated action buttons render.
StickerPack _compliantPack() => StickerPack(
  id: 'pack1',
  name: 'Doggos',
  stickers: [
    _sticker('p_rex', emojis: const ['🐶']),
    _sticker('p_bella', emojis: const ['🐕']),
    _sticker('p_charlie', emojis: const ['🦴']),
  ],
);

/// Records how the screen drives the installer without touching real IO or the
/// platform channel. [installed] gates the not-installed branch; [fail] makes
/// [addToWhatsApp] throw; [delay] holds the call open so the busy spinner is
/// observable mid-flight.
class _FakeInstaller extends WhatsAppPackInstaller {
  _FakeInstaller({
    this.installed = true,
    this.fail = false,
    this.delay = Duration.zero,
  });

  final bool installed;
  final bool fail;
  final Duration delay;

  bool installedChecked = false;
  bool addCalled = false;
  StickerPack? addedPack;
  Map<String, StickerProject>? addedProjects;

  @override
  Future<bool> isWhatsAppInstalled() async {
    installedChecked = true;
    return installed;
  }

  @override
  Future<void> addToWhatsApp(
    StickerPack pack,
    Map<String, StickerProject> projects, {
    Directory? baseDir,
  }) async {
    addCalled = true;
    addedPack = pack;
    addedProjects = projects;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw Exception('export failed');
  }
}

/// Records how the screen drives the Telegram share flow.
class _FakeShare extends TelegramPackShare {
  _FakeShare({this.fail = false, this.delay = Duration.zero});

  final bool fail;
  final Duration delay;

  bool shareCalled = false;
  StickerPack? sharedPack;
  Map<String, StickerProject>? sharedProjects;

  @override
  Future<TelegramPackExport> share(
    StickerPack pack,
    Map<String, StickerProject> projects, {
    Directory? baseDir,
  }) async {
    shareCalled = true;
    sharedPack = pack;
    sharedProjects = projects;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (fail) throw Exception('share failed');
    return const TelegramPackExport(
      files: [],
      emojis: [],
      shortNameSuggestion: 'doggos_by_sm',
      animated: false,
    );
  }
}

/// Pumps [PackDetailScreen] for [pack] with the installer / share providers
/// optionally overridden by fakes.
Future<void> _pumpDetailWith(
  WidgetTester tester, {
  required StickerPack pack,
  WhatsAppPackInstaller? installer,
  TelegramPackShare? share,
}) async {
  final repo = _FakePackRepository([pack]);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/pack/${pack.id}'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/pack/:id',
        builder: (context, state) =>
            PackDetailScreen(packId: state.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        packRepositoryProvider.overrideWithValue(repo),
        savedProjectsProvider.overrideWith((ref) => _projects),
        if (installer != null)
          whatsAppPackInstallerProvider.overrideWithValue(installer),
        if (share != null) telegramPackShareProvider.overrideWithValue(share),
      ],
      child: MaterialApp.router(
        theme: buildStickerTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Lets the SmToast auto-dismiss (1.5 s hold + reverse) fully unwind so no
/// pending timers survive into teardown.
Future<void> _dismissToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1700));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1080, 2400);
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

  testWidgets('loads the pack with meta and live compliance feedback', (
    tester,
  ) async {
    await _pumpDetail(tester);

    expect(find.text('Doggos'), findsWidgets); // title (+ maybe elsewhere)
    expect(find.text('2 / 30'), findsOneWidget);
    expect(find.text('Static'), findsOneWidget);
    // < 3 stickers → blocking, so the banner says not ready.
    expect(find.text('Not ready yet'), findsOneWidget);
    expect(find.text('Add stickers'), findsOneWidget);
    // The resolved project names render on their rows.
    expect(find.text('Rex'), findsOneWidget);
    expect(find.text('Bella'), findsOneWidget);
  });

  testWidgets('tagging an untagged sticker persists the emoji', (tester) async {
    final repo = await _pumpDetail(tester);

    // Bella is untagged → shows the tag prompt.
    expect(find.text('+ Add emoji tags'), findsOneWidget);
    await tester.tap(find.text('+ Add emoji tags'));
    await tester.pumpAndSettle();

    // Pick a quick emoji, then save.
    expect(find.text('Emoji tags'), findsOneWidget);
    await tester.tap(find.text('🎉'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Both stickers now tagged → the prompt is gone.
    expect(find.text('+ Add emoji tags'), findsNothing);

    final saved = await repo.load('pack1');
    final bella = saved!.stickers.firstWhere((s) => s.projectId == 'p_bella');
    expect(bella.emojis, ['🎉']);
  });

  testWidgets('adds an eligible saved sticker from the sheet', (tester) async {
    final repo = await _pumpDetail(tester);

    await tester.tap(find.text('Add stickers'));
    await tester.pumpAndSettle();

    // Only Charlie is eligible (Rex & Bella are already in the pack).
    expect(find.text('Add a sticker'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    await tester.tap(find.text('Charlie'));
    await tester.pumpAndSettle();

    expect(find.text('3 / 30'), findsOneWidget);
    expect((await repo.load('pack1'))!.count, 3);
  });

  testWidgets('removing a sticker updates the pack', (tester) async {
    final repo = await _pumpDetail(tester);

    // Each sticker row has a close button; remove the first.
    expect(find.byIcon(Icons.close), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();

    expect(find.text('1 / 30'), findsOneWidget);
    expect((await repo.load('pack1'))!.count, 1);
  });

  group('pack action buttons', () {
    testWidgets('render only when the pack is compliant', (tester) async {
      await _pumpDetailWith(tester, pack: _compliantPack());

      expect(find.text('Ready to share'), findsOneWidget);
      expect(find.text('Add to WhatsApp'), findsOneWidget);
      expect(find.text('Add to Telegram'), findsOneWidget);
    });

    testWidgets('are hidden while the pack has a blocking issue', (
      tester,
    ) async {
      // The 2-sticker seed is under the 3-sticker minimum → error-severity.
      await _pumpDetailWith(tester, pack: _seedPack());

      expect(find.text('Not ready yet'), findsOneWidget);
      expect(find.text('Add to WhatsApp'), findsNothing);
      expect(find.text('Add to Telegram'), findsNothing);
    });

    testWidgets('Add to WhatsApp does not install when WhatsApp is absent', (
      tester,
    ) async {
      final installer = _FakeInstaller(installed: false);
      await _pumpDetailWith(
        tester,
        pack: _compliantPack(),
        installer: installer,
      );

      await tester.tap(find.text('Add to WhatsApp'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(installer.installedChecked, isTrue);
      expect(
        installer.addCalled,
        isFalse,
        reason: 'no export without WhatsApp',
      );
      expect(find.textContaining('installed'), findsOneWidget);

      await _dismissToast(tester);
    });

    testWidgets('Add to WhatsApp success installs with the pack + projects', (
      tester,
    ) async {
      final installer = _FakeInstaller(); // installed, succeeds
      await _pumpDetailWith(
        tester,
        pack: _compliantPack(),
        installer: installer,
      );

      await tester.tap(find.text('Add to WhatsApp'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(installer.addCalled, isTrue);
      expect(installer.addedPack?.id, 'pack1');
      expect(installer.addedPack?.count, 3);
      // The resolved projectId → project map the exporter renders from.
      expect(
        installer.addedProjects?.keys,
        containsAll(<String>['p_rex', 'p_bella', 'p_charlie']),
      );

      await _dismissToast(tester);
    });

    testWidgets('Add to WhatsApp failure toasts and clears the busy state', (
      tester,
    ) async {
      final installer = _FakeInstaller(
        fail: true,
        delay: const Duration(milliseconds: 40),
      );
      await _pumpDetailWith(
        tester,
        pack: _compliantPack(),
        installer: installer,
      );

      await tester.tap(find.text('Add to WhatsApp'));
      await tester.pump();
      // The delayed export holds the button in its busy state.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 80)); // delay → throw
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(installer.addCalled, isTrue);
      expect(find.textContaining('try again'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'the finally block resets the busy flag',
      );

      await _dismissToast(tester);
    });

    testWidgets('Add to Telegram success shares the pack + projects', (
      tester,
    ) async {
      final share = _FakeShare();
      await _pumpDetailWith(tester, pack: _compliantPack(), share: share);

      await tester.tap(find.text('Add to Telegram'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(share.shareCalled, isTrue);
      expect(share.sharedPack?.id, 'pack1');
      expect(
        share.sharedProjects?.keys,
        containsAll(<String>['p_rex', 'p_bella', 'p_charlie']),
      );

      await _dismissToast(tester);
    });

    testWidgets('Add to Telegram failure toasts and clears the busy state', (
      tester,
    ) async {
      final share = _FakeShare(
        fail: true,
        delay: const Duration(milliseconds: 40),
      );
      await _pumpDetailWith(tester, pack: _compliantPack(), share: share);

      await tester.tap(find.text('Add to Telegram'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(share.shareCalled, isTrue);
      expect(find.textContaining('try again'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _dismissToast(tester);
    });
  });
}
