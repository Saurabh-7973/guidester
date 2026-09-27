/// Hosted in-app tester feedback for Flutter.
///
/// Three lines of integration, no subclassing, no router integration:
///
/// ```dart
/// Guidester.init(
///   apiKey: const String.fromEnvironment('GUIDESTER_KEY'),
///   endpoint: const String.fromEnvironment('GUIDESTER_ENDPOINT'),
/// );
///
/// MaterialApp(
///   navigatorObservers: [Guidester.observer],
///   builder: (context, child) => GuidesterOverlay(child: child!),
/// );
/// ```
library;

export 'src/guidester.dart' show Guidester;
export 'src/overlay.dart' show GuidesterOverlay;
export 'src/screen_resolver.dart' show GuidesterRouteObserver, GuidesterScreen;
