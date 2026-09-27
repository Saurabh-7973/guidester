import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_build.dart';

/// On the web, `flutter build web` writes `version.json` next to the app with
/// the same version and build number. Reading it keeps package_info_plus out
/// of web builds, which is what lets the package compile to WebAssembly.
Future<AppBuild?> readAppBuild() async {
  final response = await http.get(Uri.base.resolve('version.json'));
  if (response.statusCode != 200) return null;
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) return null;
  String? field(String key) =>
      decoded[key] is String ? decoded[key] as String : null;
  return AppBuild(
    version: field('version'),
    buildNumber: field('build_number'),
  );
}
