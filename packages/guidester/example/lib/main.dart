// Example app for the guidester SDK.
//
// Exists to prove §5.5: the same SDK resolves screen names under a plain
// named-route Navigator AND under GoRouter, with no host changes and no
// routing dependency inside the package itself.
//
// Run with:
//   flutter run --dart-define=GUIDESTER_KEY=<project api_key>
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:guidester/guidester.dart';
// ignore: implementation_imports
import 'package:guidester/src/api_client.dart' show ApiClient;

// The whole install, and the same two lines the README and the dashboard's
// onboarding step show. No enabled flag: an empty key is the kill switch, so a
// build with no dart-define ships inert. The endpoint is your own deployment
// of the ingest function; the package ships no default.
void main() {
  Guidester.init(
    apiKey: const String.fromEnvironment('GUIDESTER_KEY'),
    endpoint: const String.fromEnvironment('GUIDESTER_ENDPOINT'),
  );
  runApp(const ExampleApp());
}

/// Lets us flip the whole app between the two routing styles at runtime.
enum RouterStyle { navigator, goRouter }

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, this.client, this.frameSize, this.title});

  /// The browser tab's title on the web. The inner app sets it, so the demo
  /// page passes its own.
  final String? title;

  /// Where comments go. Null is the real network; the in-browser demo
  /// (`web_demo.dart`) passes one that puts them on its own board instead.
  final ApiClient? client;

  /// The screen size to report when the app is drawn inside a phone frame on a
  /// larger page. A nested app otherwise reads the browser window's size, and
  /// the bubble lands outside the frame.
  final Size? frameSize;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  RouterStyle _style = RouterStyle.navigator;

  void _switchTo(RouterStyle style) => setState(() => _style = style);

  @override
  Widget build(BuildContext context) {
    Widget overlay(BuildContext context, Widget? child) {
      final overlay = GuidesterOverlay(client: widget.client, child: child!);
      final size = widget.frameSize;
      if (size == null) return overlay;
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: size,
          padding: const EdgeInsets.only(top: 24),
          viewPadding: const EdgeInsets.only(top: 24),
        ),
        child: overlay,
      );
    }

    return _style == RouterStyle.navigator
        ? _NavigatorApp(
            onSwitch: () => _switchTo(RouterStyle.goRouter),
            overlay: overlay,
            title: widget.title,
          )
        : _GoRouterApp(
            onSwitch: () => _switchTo(RouterStyle.navigator),
            overlay: overlay,
            title: widget.title,
          );
  }
}

// ---------------------------------------------------------------------------
// Tree 1 — named Navigator routes. Exercises resolver layer 2.
// ---------------------------------------------------------------------------

class _NavigatorApp extends StatelessWidget {
  const _NavigatorApp({
    required this.onSwitch,
    required this.overlay,
    this.title,
  });

  final VoidCallback onSwitch;
  final TransitionBuilder overlay;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title ?? 'Guidester example (Navigator)',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      // The two integration lines. Nothing else in the host changes.
      navigatorObservers: [Guidester.observer],
      builder: overlay,
      initialRoute: '/home',
      routes: {
        '/home': (_) => _Demo(
          title: 'Navigator: /home',
          expectation: 'layer 2 — named route',
          onSwitch: onSwitch,
          links: const [('/checkout', 'Go to /checkout')],
        ),
        '/checkout': (_) => _Demo(
          title: 'Navigator: /checkout',
          expectation: 'layer 2 — named route',
          onSwitch: onSwitch,
          links: const [('/unnamed', 'Go to an unnamed route')],
        ),
        '/unnamed': (_) => _Demo(
          title: 'Unnamed route',
          // This page is itself the named route '/unnamed'. The unnamed case
          // is the ProfileScreen its button pushes.
          expectation:
              'layer 2 — named route; the button pushes one with no name',
          onSwitch: onSwitch,
          links: const [],
          // Pushed without settings.name below, so layer 2 declines.
          pushUnnamed: true,
        ),
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tree 2 — GoRouter. Exercises resolver layer 3, with no go_router dependency
// inside the guidester package itself.
// ---------------------------------------------------------------------------

class _GoRouterApp extends StatelessWidget {
  _GoRouterApp({required this.onSwitch, required this.overlay, this.title});

  final VoidCallback onSwitch;
  final TransitionBuilder overlay;
  final String? title;

  // Deliberately NOT passing `observers: [Guidester.observer]` here.
  //
  // GoRouter does set `settings.name` on the routes it pushes, so attaching
  // the observer makes layer 2 win and produce the same answer. That is fine
  // in production, but it means layer 3 never runs — and layer 3 is the part
  // that has to work for routers that carry no route names at all. Leaving the
  // observer off is what actually exercises it.
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => _Demo(
          title: 'GoRouter: /',
          expectation: 'layer 3 declines on "/" — falls through to layer 4',
          onSwitch: onSwitch,
          links: const [('/settings/profile', 'Go to /settings/profile')],
          go: true,
        ),
      ),
      GoRoute(
        path: '/settings/profile',
        builder: (_, _) => _Demo(
          title: 'GoRouter: /settings/profile',
          expectation: 'layer 3 — Router URI → SETTINGS/PROFILE',
          onSwitch: onSwitch,
          links: const [('/', 'Back to /')],
          go: true,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: title ?? 'Guidester example (GoRouter)',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      routerConfig: _router,
      builder: overlay,
    );
  }
}

// ---------------------------------------------------------------------------

class _Demo extends StatelessWidget {
  const _Demo({
    required this.title,
    required this.expectation,
    required this.onSwitch,
    required this.links,
    this.go = false,
    this.pushUnnamed = false,
  });

  final String title;
  final String expectation;
  final VoidCallback onSwitch;
  final List<(String, String)> links;
  final bool go;
  final bool pushUnnamed;

  @override
  Widget build(BuildContext context) {
    final resolved = Guidester.debugResolveScreen(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resolver says',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'name  : ${resolved.name}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  Text(
                    'layer : ${resolved.layer}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'expected: $expectation',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Redaction, live. Pin a comment on this screen: the card number
          // arrives as a solid block, in the thumbnail and on the board.
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved card',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  GuidesterRedact(
                    child: Text(
                      '4242 4242 4242 4242',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 16),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Wrapped in GuidesterRedact: never in a screenshot.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!Guidester.isEnabled)
            const Card(
              color: Color(0xFFFFF7ED),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Guidester is OFF. Relaunch with:\n'
                  '--dart-define=GUIDESTER=true '
                  '--dart-define=GUIDESTER_KEY=<key>',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          for (final (route, label) in links)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton(
                onPressed: () => go
                    ? context.go(route)
                    : Navigator.of(context).pushNamed(route),
                child: Text(label),
              ),
            ),
          if (pushUnnamed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfileScreen(),
                  ),
                ),
                child: const Text('Push ProfileScreen with no route name'),
              ),
            ),
          const SizedBox(height: 8),
          // Throwing on purpose, so the next comment demonstrably carries a
          // stack. The framework handles it exactly as it would any other
          // build error — red screen in debug, console dump — because the
          // recorder chains rather than replaces.
          OutlinedButton(
            onPressed: () => Future<void>.error(
              StateError('demo error from the example app'),
              StackTrace.current,
            ),
            child: const Text('Throw an error, then comment'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onSwitch,
            child: const Text('Switch router style'),
          ),
        ],
      ),
    );
  }
}

/// Pushed with no route name, so layers 1-3 all decline and layer 4's
/// class-name heuristic has to produce PROFILE.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final resolved = Guidester.debugResolveScreen(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Unnamed route')),
      body: Center(
        child: Text(
          'name : ${resolved.name}\nlayer: ${resolved.layer}\n\n'
          'expected: PROFILE at layer 4',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
