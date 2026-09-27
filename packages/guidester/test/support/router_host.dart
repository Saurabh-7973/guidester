import 'package:flutter/material.dart';

/// A minimal Navigator 2.0 configuration: enough to put a real [Router] in the
/// tree at a known location, with no dependency on `go_router` — which the SDK
/// must never take, and which its tests must not take either, or they stop
/// testing the router-agnostic claim.
///
/// [child] is what the delegate's Navigator shows. Nesting a second
/// `MaterialApp.router` in there is how the nested-Router case is built.
RouterConfig<Object> routerConfigFor({
  required String initialPath,
  Widget child = const _Blank(),
}) {
  return RouterConfig<Object>(
    routeInformationProvider: PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(uri: Uri.parse(initialPath)),
    ),
    routeInformationParser: PathParser(),
    routerDelegate: PathDelegate(child: child),
  );
}

class _Blank extends StatelessWidget {
  const _Blank();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class PathParser extends RouteInformationParser<Uri> {
  @override
  Future<Uri> parseRouteInformation(RouteInformation routeInformation) async =>
      routeInformation.uri;

  @override
  RouteInformation restoreRouteInformation(Uri configuration) =>
      RouteInformation(uri: configuration);
}

class PathDelegate extends RouterDelegate<Uri>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Uri> {
  PathDelegate({required this.child});

  final Widget child;
  Uri _current = Uri.parse('/');

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Uri get currentConfiguration => _current;

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    _current = configuration;
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) => Navigator(
        key: navigatorKey,
        pages: [MaterialPage<void>(child: child)],
        onDidRemovePage: (_) {},
      );
}
