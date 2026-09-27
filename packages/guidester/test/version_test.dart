import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/src/version.dart';

void main() {
  test('guidesterSdkVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version line');
    expect(guidesterSdkVersion, match!.group(1));
  });
}
