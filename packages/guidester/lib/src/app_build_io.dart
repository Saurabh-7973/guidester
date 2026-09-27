import 'package:package_info_plus/package_info_plus.dart';

import 'app_build.dart';

/// Everywhere but the web: the platform's own package info.
Future<AppBuild?> readAppBuild() async {
  final info = await PackageInfo.fromPlatform();
  return AppBuild(
    version: info.version,
    buildNumber: info.buildNumber,
    packageName: info.packageName,
  );
}
