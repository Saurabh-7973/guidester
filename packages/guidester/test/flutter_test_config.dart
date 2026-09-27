import 'dart:async';

import 'package:guidester/src/guidester.dart';
import 'package:guidester/src/screen_resolver.dart';

/// Runs once before every test file in this package.
///
/// The launch ping is a real network call on a real timer. A timer still
/// pending when a widget test finishes fails that test, and every test here
/// that enables the SDK mounts an overlay — so the ping is off by default and
/// the tests that are about the ping switch it on for themselves.
/// The console diagnostics are off here for the same reason: the mount warning
/// is a five-second timer, and most tests in this package never mount an
/// overlay on purpose. Their own tests turn them back on, which is also the
/// only way to be sure the tests are testing them.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Guidester.debugLaunchPingEnabled = false;
  Guidester.debugMountWarningEnabled = false;
  Guidester.debugPrintResolvedScreen = false;
  ScreenResolver.debugRouteWarningEnabled = false;
  await testMain();
}
