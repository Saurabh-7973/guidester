import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs once before every test file in this package.
///
/// The test renderer ships a placeholder font and ignores `fontFamily`, so a
/// golden rendered without this shows uniform boxes instead of type — which
/// makes a screenshot of a design worthless as evidence. Loading the same
/// four Inter weights the app bundles makes the golden match the browser.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // One loader, four faces: weight is read from each file's own metadata, so
  // four separate loaders under the same family would fight over it.
  final inter = FontLoader('Inter');
  for (final file in const [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]) {
    final bytes = File('fonts/$file').readAsBytesSync();
    inter.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await inter.load();

  final mono = FontLoader('JetBrains Mono');
  for (final file in const ['JetBrainsMono-Regular.ttf']) {
    final bytes = File('fonts/$file').readAsBytesSync();
    mono.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await mono.load();

  // Without this every Icon renders as a filled box, so a golden claims the
  // shell is broken when only the test renderer is. The font ships inside the
  // Flutter SDK; if it ever moves, skip it rather than fail every test file.
  // resolvedExecutable is <flutter>/bin/cache/dart-sdk/bin/dart, and the fonts
  // live at <flutter>/bin/cache/artifacts/material_fonts — but the depth
  // differs between a git checkout and a packaged SDK, so walk up and look
  // rather than counting directories.
  for (
    var dir = File(Platform.resolvedExecutable).parent;
    dir.path != dir.parent.path;
    dir = dir.parent
  ) {
    final icons = File(
      '${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
      break;
    }
  }

  await testMain();
}
