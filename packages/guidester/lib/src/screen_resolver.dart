import 'package:flutter/widgets.dart';

/// Which layer produced a screen name, and what it produced.
class ScreenResolution {
  const ScreenResolution(this.name, this.layer);

  /// Normalised screen name, or `UNKNOWN` when every layer declined.
  final String name;

  /// 1 manual, 2 navigator observer, 3 router URI, 4 widget heuristic,
  /// 0 nothing matched.
  final int layer;

  @override
  String toString() => 'ScreenResolution($name, layer $layer)';
}

/// Observes `Navigator` pushes to keep a stack of named routes.
///
/// Layer 2 of the resolver. Covers named routes and most GoRouter setups,
/// which push routes carrying a `settings.name`.
class GuidesterRouteObserver extends NavigatorObserver {
  final List<String> stack = [];

  /// The route on top of the Navigator this observer watches. The overlay
  /// hangs a local history entry on it while a sheet is open, so Android
  /// Back closes the sheet instead of popping the host's screen.
  Route<dynamic>? topRoute;

  String? _nameOf(Route<dynamic>? r) {
    final n = r?.settings.name;
    return (n == null || n.isEmpty) ? null : n;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    topRoute = route;
    final n = _nameOf(route);
    if (n != null) stack.add(n);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, topRoute)) topRoute = previousRoute;
    if (stack.isNotEmpty) stack.removeLast();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (identical(oldRoute, topRoute)) topRoute = newRoute;
    final n = _nameOf(newRoute);
    if (n == null) return;
    if (stack.isNotEmpty) stack.removeLast();
    stack.add(n);
  }

  /// The current route name, or null when this observer cannot be trusted.
  ///
  /// `navigator` is null whenever the observer is not attached to a live
  /// Navigator — it was never wired up, or the tree it watched is gone. The
  /// stack it accumulated is then stale, and a stale name is worse than no
  /// name: it beats the layers that can still see the truth, and reports a
  /// screen the tester is not looking at. Decline instead.
  String? get current {
    if (navigator == null) return null;
    return stack.isEmpty ? null : stack.last;
  }

  /// Raw stack tip, ignoring attachment. Only for tests.
  @visibleForTesting
  String? get debugCurrentIgnoringAttachment =>
      stack.isEmpty ? null : stack.last;

  /// Last 5 screens, oldest first. Shipped as `context.route_stack`.
  /// Empty when detached, for the same reason as [current].
  List<String> get breadcrumb {
    if (navigator == null) return const [];
    return stack.length <= 5 ? List.of(stack) : stack.sublist(stack.length - 5);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, topRoute)) topRoute = previousRoute;
  }

  void debugReset() {
    stack.clear();
    topRoute = null;
  }
}

/// Marks a subtree as belonging to a named screen. Layer 1, scoped.
///
/// Most apps never need it: named routes and Router URIs are read on their
/// own. Wrap a screen when the resolver cannot infer a good name, or when the
/// app is built with `--obfuscate`, which removes the class-name fallback:
///
/// ```dart
/// class CheckoutScreen extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) => GuidesterScreen(
///         name: 'CHECKOUT',
///         child: Scaffold(/* ... */),
///       );
/// }
/// ```
///
/// A nested [GuidesterScreen] wins over the one it sits inside, and
/// [Guidester.setScreen] wins over both.
class GuidesterScreen extends InheritedWidget {
  const GuidesterScreen({super.key, required this.name, required super.child});

  /// The screen name comments from inside this subtree are filed under, as
  /// written: `CHECKOUT`, `settings/profile`.
  final String name;

  /// The name of the nearest enclosing [GuidesterScreen], or null.
  static String? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuidesterScreen>()?.name;

  @override
  bool updateShouldNotify(GuidesterScreen oldWidget) => name != oldWidget.name;
}

/// A class whose only job is to be renamed.
///
/// `flutter build --obfuscate` rewrites Dart class names, so this one's
/// runtime name matches its literal in every build except an obfuscated one.
/// Measured on hardware: `HomeScreen` came back as `Dw`. See D67.
class GuidesterBuildProbe {
  const GuidesterBuildProbe();
}

/// Router-agnostic screen name resolution.
///
/// Four layers, first non-null wins. No dependency on `go_router`,
/// `auto_route`, `beamer` or any other routing package, and the host app
/// changes nothing.
class ScreenResolver {
  ScreenResolver._();

  /// Layer 1, global. Set via `Guidester.setScreen`.
  static String? manual;

  static const int _maxElementVisits = 2000;
  static const int _maxNameLength = 40;

  /// Suffixes that name a screen, and how strongly each one says so.
  ///
  /// A `View` is as often a component as a screen — `DropDownView`,
  /// `CardView`, `HeaderView`. A `Screen` almost never is. The rank is only
  /// consulted between a match and a match *inside* it; see [_fromWidgetTree].
  static const Map<String, int> _suffixRank = {
    'Screen': 3,
    'Page': 2,
    'View': 1,
  };

  /// Flutter's own widgets that end in one of [_suffixRank]'s suffixes and
  /// would otherwise be mistaken for a host screen.
  ///
  /// Found in the wild: a host app's onboarding resolved to `SINGLECHILDSCROLL`
  /// because `SingleChildScrollView` ends in "View". Every scrolling screen in
  /// every app would have done the same. A wrong screen name is worse than
  /// `UNKNOWN` — `UNKNOWN` says the resolver failed, a wrong one sends you to
  /// the wrong file.
  ///
  /// Found again on 25 Sep: every `showDialog` wraps its page in
  /// `DisplayFeatureSubScreen`, so any comment filed over a dialog came back
  /// `DISPLAYFEATURESUB`. A test now scans the Flutter SDK and fails when a
  /// public widget with a screen suffix is missing here.
  static const Set<String> _frameworkTypes = {
    'SingleChildScrollView',
    'CustomScrollView',
    'NestedScrollView',
    'ScrollView',
    'BoxScrollView',
    'ListView',
    'ListWheelScrollView',
    'TwoDimensionalScrollView',
    'GridView',
    'PageView',
    'CarouselView',
    'ReorderableListView',
    'TabBarView',
    'CupertinoTabView',
    'PageStorage',
    'AndroidView',
    'UiKitView',
    'AppKitView',
    'PlatformViewLink',
    'HtmlElementView',
    'ImgElementPlatformView',
    'TextureView',
    'RawView',
    'RawKeyboardListener',
    'AnimatedSwitcher',
    'DisplayFeatureSubScreen',
    'ModalBarrierPage',
    'MaterialPage',
    'CupertinoPage',
    'OverlayPage',
    'LicensePage',
  };

  @visibleForTesting
  static Set<String> get frameworkTypes => _frameworkTypes;

  /// Resolve a screen name, reporting which layer produced it.
  ///
  /// [context] should sit below the app's `Router` and `Navigator`.
  /// [hitTestTarget] is the element under the tester's finger, used by layer 4.
  static ScreenResolution resolveDetailed(
    BuildContext? context, {
    Element? searchRoot,
    GuidesterRouteObserver? observer,
  }) {
    // A layer that produces nothing usable must DECLINE, not win with
    // 'UNKNOWN'. The root route is named '/', which normalises to nothing —
    // without this, every app's home screen would report UNKNOWN from layer 2
    // and layers 3 and 4 would never run.
    ScreenResolution? accept(String? raw, int layer) {
      if (raw == null || raw.isEmpty) return null;
      final normalized = normalize(raw);
      if (normalized == 'UNKNOWN') return null;
      return ScreenResolution(normalized, layer);
    }

    // Layer 1 — manual. Always wins.
    final byManual = accept(manual, 1) ??
        (context == null ? null : accept(GuidesterScreen.maybeOf(context), 1));
    if (byManual != null) return byManual;

    // Layer 2 — NavigatorObserver.
    final byObserver = accept(observer?.current, 2);
    if (byObserver != null) return byObserver;

    // Layer 3 — the Router URI. This is the one that makes us universal.
    if (context != null) {
      final byRouter = accept(_fromRouter(context), 3);
      if (byRouter != null) return byRouter;
    }

    // Layer 4 — widget-class heuristic.
    final root = searchRoot ?? (context is Element ? context : null);
    if (root != null) {
      final byWidget = accept(_fromWidgetTree(root), 4);
      if (byWidget != null) return byWidget;
    }

    _warnNoRouteName();
    return const ScreenResolution('UNKNOWN', 0);
  }

  /// Diagnostic 3 of 6, printed once per session rather than per tap.
  ///
  /// A dashboard filling with `UNKNOWN` is almost always a Navigator 1.0 app
  /// with unnamed routes and no observer attached. Layer 3 answers for every
  /// `Router`-based app, which is why the observer is not in the three-line
  /// install — but the apps that still need it get no hint at all without
  /// this, and a wrong screen name sends a developer to the wrong file.
  static bool _warnedNoRoute = false;

  /// Off across this package's own suite, which resolves UNKNOWN deliberately
  /// and often.
  static bool debugRouteWarningEnabled = true;

  static void _warnNoRouteName() {
    if (_warnedNoRoute || !debugRouteWarningEnabled) return;
    _warnedNoRoute = true;
    // An obfuscated build is a different failure with the same symptom, and
    // the Navigator 1.0 advice below is actively wrong for it: no observer
    // brings layer 4 back, because there are no class names left to read.
    // Usually already said at init; this covers a resolve that happens first.
    if (looksObfuscated) {
      warnIfObfuscated();
      return;
    }
    debugPrint(
      '[guidester] no route name and no Router found, so this screen reports '
      'UNKNOWN. If you use Navigator 1.0 named routes, add Guidester.observer '
      'to your MaterialApp navigatorObservers. Otherwise wrap the screen in '
      'GuidesterScreen(name: ...) or call Guidester.setScreen().',
    );
  }

  static bool _warnedObfuscated = false;

  /// Diagnostic 6 of 6, said once, and said at `Guidester.init` rather than at
  /// the first failed resolve.
  ///
  /// `--obfuscate` is the recommended setting for a Play release, and it takes
  /// every layer 4 tag with it in one go: `HomeScreen` compiles to `Dw`, no
  /// suffix matches, and every screen the heuristic named reports `UNKNOWN`.
  /// A developer who never files a comment on their own machine never
  /// resolves a screen, so a warning that waits for a failed resolve waits
  /// forever while the dashboard fills with `UNKNOWN` from the testers. D67.
  static void warnIfObfuscated() {
    if (_warnedObfuscated || !looksObfuscated) return;
    _warnedObfuscated = true;
    debugPrint(
      '[guidester] this build is obfuscated, so the widget-class heuristic '
      '(layer 4) cannot name screens and they report UNKNOWN. Route names and '
      'Router URIs still work — layers 1 to 3 are unaffected. Wrap screens in '
      'GuidesterScreen(name: ...), call Guidester.setScreen(), or drop '
      '--obfuscate from tester builds.',
    );
  }

  /// Whether this build's Dart class names survived compilation.
  ///
  /// Layer 4 reads `runtimeType.toString()` and nothing else, so an obfuscated
  /// build has no layer 4 at all. Nothing about that is visible from inside a
  /// debug build or a widget test, which is why this compares a class this
  /// package owns against its own literal name.
  static bool get looksObfuscated =>
      debugForceObfuscated ??
      debugIsObfuscatedName(const GuidesterBuildProbe().runtimeType.toString());

  /// A name is obfuscated when it is not the one written in the source.
  @visibleForTesting
  static bool debugIsObfuscatedName(String observed) =>
      observed != 'GuidesterBuildProbe';

  /// Forces the answer in a test. An obfuscated build cannot be produced by
  /// one, so the branch it takes has to be reachable some other way.
  @visibleForTesting
  static bool? debugForceObfuscated;

  @visibleForTesting
  static void debugResetWarning() {
    _warnedNoRoute = false;
    _warnedObfuscated = false;
  }

  /// Convenience wrapper returning just the name.
  static String resolve(
    BuildContext? context, {
    Element? searchRoot,
    GuidesterRouteObserver? observer,
  }) =>
      resolveDetailed(context, searchRoot: searchRoot, observer: observer).name;

  /// `Router` is Flutter core, not `go_router`. Every declarative router
  /// builds on it, so reading it here catches GoRouter, auto_route and Beamer
  /// with zero dependencies and zero host changes.
  static String? _fromRouter(BuildContext context) {
    try {
      // Look UP first: correct for MaterialApp (Navigator 1.0) hosts, where
      // `builder` runs below the Router.
      final fromAbove = _pathOf(Router.maybeOf(context));
      if (fromAbove != null) return fromAbove;

      // Then look DOWN. With `MaterialApp.router`, `builder` wraps the Router
      // from above, so the Router is inside our child subtree and an ancestor
      // lookup finds nothing. Found in a real host app: every screen fell
      // through to the layer 4 heuristic even though the router had proper
      // paths like /today and /library.
      if (context is Element) {
        final below = _findRouterBelow(context);
        final fromBelow = _pathOf(below);
        if (fromBelow != null) return fromBelow;
      }
      return null;
    } catch (_) {
      // A Router mid-rebuild or absent must never break capture.
      return null;
    }
  }

  static String? _pathOf(Object? router) {
    final uri = switch (router) {
      final Router<Object?> r => r.routeInformationProvider?.value.uri,
      _ => null,
    };
    final path = uri?.path;
    return (path == null || path.isEmpty) ? null : path;
  }

  /// Nearest [Router] in the subtree below [start], or null.
  ///
  /// Nested Routers resolve to the **outer** one, and that is the intent, not
  /// an accident of the walk order. The outer Router holds the location the
  /// whole app is at, which is what a developer reading a bug report needs; an
  /// inner Router driving a sub-flow reports `/step-2` of nothing in
  /// particular. Pinned by a test in `screen_resolver_test.dart`.
  static Router<Object?>? _findRouterBelow(Element start) {
    Router<Object?>? found;
    var visited = 0;
    void walk(Element element) {
      if (found != null || visited > _maxElementVisits) return;
      visited++;
      final w = element.widget;
      if (w is Router<Object?>) {
        found = w;
        return;
      }
      element.visitChildren(walk);
    }

    walk(start);
    return found;
  }

  /// Find the widget below [start] that best names the current screen, by
  /// type-name suffix, and return that name with the suffix stripped.
  ///
  /// Searching downward rather than up from a hit-tested element is deliberate:
  /// mapping a hit test back to an [Element] only works in debug builds, and
  /// this must behave identically in release.
  ///
  /// Two rules decide between candidates, and the difference between them is
  /// whether one contains the other:
  ///
  /// * **A match in a different branch always wins**, because the walk visits
  ///   the overlay's entries in paint order and the last one is the route on
  ///   top. A pushed `DetailsView` beats the `HomeScreen` still mounted
  ///   underneath it, whatever the suffixes are.
  /// * **A match nested inside another only wins if it ranks at least as
  ///   high**, because a widget rendered inside a screen is usually a piece of
  ///   that screen. Snapdrop's `HomeScreen` renders `DropDownView` inline, and
  ///   keeping the deepest match unconditionally made its main screen report
  ///   `DROPDOWN`. An equal rank still wins, which keeps the shell case right:
  ///   a `HomeScreen` shell rendering the selected `ProfileScreen` reports
  ///   `PROFILE`.
  ///
  /// This is a heuristic and it can still be wrong — a screen named
  /// `CartView` rendering a `SummaryScreen` component reports `SUMMARY`.
  /// `GuidesterScreen(name: ...)` remains the answer that cannot be wrong.
  /// The walk is capped so a deep tree cannot stall the tap handler.
  static String? _fromWidgetTree(Element start) {
    String? found;
    var visited = 0;

    // The rank of the nearest match on the path from [start] to this element,
    // 0 when there is none. It travels down a branch and not across, which is
    // what makes a sibling route free to overrule and a child unable to.
    void walk(Element element, int ancestorRank) {
      // No depth cap: searching downward starts above MaterialApp's own
      // machinery, which is already deeper than 40 elements before the host's
      // screen appears. The visit budget is what bounds the work.
      if (visited > _maxElementVisits) return;
      visited++;
      var rankBelow = ancestorRank;
      final typeName = element.widget.runtimeType.toString();
      if (!typeName.startsWith('_') && !_frameworkTypes.contains(typeName)) {
        for (final MapEntry(key: suffix, value: rank) in _suffixRank.entries) {
          if (typeName.length > suffix.length && typeName.endsWith(suffix)) {
            if (rank >= ancestorRank) {
              found = typeName.substring(0, typeName.length - suffix.length);
              rankBelow = rank;
            }
            break;
          }
        }
      }
      element.visitChildren((child) => walk(child, rankBelow));
    }

    walk(start, 0);
    return (found == null || found!.isEmpty) ? null : found;
  }

  /// Uppercase, strip a leading `/`, turn `_` and `-` into spaces, cap length.
  ///
  /// `/checkout/payment` becomes `CHECKOUT/PAYMENT`; `HomeScreen` becomes `HOME`.
  static String normalize(String raw) {
    var s = raw.trim();
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    s = s.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    if (s.isEmpty) return 'UNKNOWN';
    s = s.toUpperCase();
    return s.length <= _maxNameLength ? s : s.substring(0, _maxNameLength);
  }
}
