/// This package's version, as reported in every comment's `sdk_version`.
///
/// A package cannot read its own pubspec at runtime, so this is a copy.
/// `test/version_test.dart` fails when it and `pubspec.yaml` disagree; bump
/// both together. Until 0.4.0 this was a hard-coded `'0.1.0'` default, so
/// every comment filed before this change reports `sdk_version=0.1.0`
/// whatever SDK it came from.
const String guidesterSdkVersion = '0.5.5';
