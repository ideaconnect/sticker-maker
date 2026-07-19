import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/about/bundled_licenses.dart';
import 'features/home/project_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  // Cold launch is the safe moment (no editor open, no undo stacks) to drop
  // orphaned image/mask files — e.g. superseded erase masks (#76). The sweep
  // does its filesystem work inside Isolate.run, so it never competes with
  // first-frame work on the UI isolate.
  unawaited(
    ProjectRepository().sweepOrphanAssets().then((_) => 0, onError: (_) => 0),
  );
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF141019),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: StickerMakerApp()));
}
