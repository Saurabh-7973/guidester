/// The host app's version and build number, however the platform exposes them.
class AppBuild {
  const AppBuild({this.version, this.buildNumber, this.packageName});

  final String? version;
  final String? buildNumber;
  final String? packageName;
}
