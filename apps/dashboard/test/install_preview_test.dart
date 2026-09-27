import 'dart:io';

import 'package:dashboard/src/widgets/onboarding_previews.dart';
import 'package:flutter_test/flutter_test.dart';

/// The preview told a developer to depend on `^0.1.0` while the package was
/// at 0.5.0. It reads the SDK's own pubspec, so the two cannot drift.
void main() {
  test('the install preview names the SDK version that ships', () {
    final pubspec = File(
      '../../packages/guidester/pubspec.yaml',
    ).readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    expect(InstallPreview.dependencyLine, '  guidester: ^$version');
  });
}
