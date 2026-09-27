import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guidester/src/screen_resolver.dart';

import 'support/router_host.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.child});

  /// Lets a test nest another matching widget inside this one, which is how a
  /// real host app produced the wrong tag.
  final Widget? child;

  @override
  Widget build(BuildContext context) => child ?? const SizedBox.shrink();
}

class CheckoutPage extends StatelessWidget {
  const CheckoutPage({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class PlainWidget extends StatelessWidget {
  const PlainWidget({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A host wrapper that ends in a matching suffix but is not a screen — the
/// mirror image of the nested-component case.
class ShellView extends StatelessWidget {
  const ShellView({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class DetailsView extends StatelessWidget {
  const DetailsView({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  setUp(() => ScreenResolver.manual = null);

  group('normalize', () {
    test('uppercases', () => expect(ScreenResolver.normalize('home'), 'HOME'));
    test(
      'strips leading slash',
      () => expect(ScreenResolver.normalize('/checkout'), 'CHECKOUT'),
    );
    test('keeps nested paths', () {
      expect(ScreenResolver.normalize('/checkout/payment'), 'CHECKOUT/PAYMENT');
    });
    test('underscores and dashes become spaces', () {
      expect(ScreenResolver.normalize('order_details'), 'ORDER DETAILS');
      expect(ScreenResolver.normalize('order-details'), 'ORDER DETAILS');
    });
    test('caps at 40 characters', () {
      expect(ScreenResolver.normalize('x' * 60).length, 40);
    });
    test('empty and slash-only fall back to UNKNOWN', () {
      expect(ScreenResolver.normalize(''), 'UNKNOWN');
      expect(ScreenResolver.normalize('/'), 'UNKNOWN');
    });
  });

  group('layer 1 — manual', () {
    testWidgets('setScreen wins over everything', (tester) async {
      ScreenResolver.manual = 'CHECKOUT';
      final observer = GuidesterRouteObserver();
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx, observer: observer);
      expect(r.name, 'CHECKOUT');
      expect(r.layer, 1);
    });

    testWidgets('GuidesterScreen ancestor also resolves at layer 1',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GuidesterScreen(name: 'PAYMENT', child: HomeScreen()),
        ),
      );
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx);
      expect(r.name, 'PAYMENT');
      expect(r.layer, 1);
    });
  });

  group('layer 2 — navigator observer', () {
    testWidgets('a named route on a live Navigator resolves at layer 2',
        (tester) async {
      final observer = GuidesterRouteObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          initialRoute: '/orders',
          routes: {'/orders': (_) => const PlainWidget()},
        ),
      );
      final ctx = tester.element(find.byType(PlainWidget));
      final r = ScreenResolver.resolveDetailed(ctx, observer: observer);
      expect(r.name, 'ORDERS');
      expect(r.layer, 2);
    });

    test('a detached observer declines rather than reporting a stale name', () {
      final o = GuidesterRouteObserver()..stack.addAll(['/home', '/orders']);
      // Never attached to a Navigator, so `navigator` is null.
      expect(o.navigator, isNull);
      expect(o.debugCurrentIgnoringAttachment, '/orders');
      expect(o.current, isNull, reason: 'stale stack must not win');
      expect(o.breadcrumb, isEmpty);
    });

    testWidgets('a detached observer lets layer 4 resolve instead',
        (tester) async {
      final stale = GuidesterRouteObserver()..stack.add('/stale-screen');
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx, observer: stale);
      expect(r.name, 'HOME');
      expect(r.layer, 4);
    });

    test('push, replace and pop keep the stack correct', () {
      final o = GuidesterRouteObserver();
      Route<void> r(String? name) => PageRouteBuilder(
            settings: RouteSettings(name: name),
            pageBuilder: (_, __, ___) => const SizedBox(),
          );
      o.didPush(r('/a'), null);
      o.didPush(r('/b'), null);
      expect(o.debugCurrentIgnoringAttachment, '/b');
      o.didReplace(newRoute: r('/c'), oldRoute: r('/b'));
      expect(o.debugCurrentIgnoringAttachment, '/c');
      o.didPop(r('/c'), r('/a'));
      expect(o.debugCurrentIgnoringAttachment, '/a');
    });

    test('unnamed routes are ignored, not pushed as empty', () {
      final o = GuidesterRouteObserver();
      o.didPush(
        PageRouteBuilder(pageBuilder: (_, __, ___) => const SizedBox()),
        null,
      );
      expect(o.debugCurrentIgnoringAttachment, isNull);
    });

    test('breadcrumb keeps the last five, oldest first', () {
      final o = GuidesterRouteObserver();
      for (final n in ['/a', '/b', '/c', '/d', '/e', '/f', '/g']) {
        o.stack.add(n);
      }
      expect(
        o.stack.sublist(o.stack.length - 5),
        ['/c', '/d', '/e', '/f', '/g'],
      );
    });

    test('popping an empty stack does not throw', () {
      final o = GuidesterRouteObserver();
      expect(
        () => o.didPop(
          PageRouteBuilder(pageBuilder: (_, __, ___) => const SizedBox()),
          null,
        ),
        returnsNormally,
      );
    });
  });

  group('layer 4 — widget-class heuristic', () {
    testWidgets('Screen suffix is stripped', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx);
      expect(r.name, 'HOME');
      expect(r.layer, 4);
    });

    testWidgets('Page suffix is stripped', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CheckoutPage()));
      final ctx = tester.element(find.byType(CheckoutPage));
      expect(ScreenResolver.resolveDetailed(ctx).name, 'CHECKOUT');
    });

    testWidgets('View suffix is stripped', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsView()));
      final ctx = tester.element(find.byType(SettingsView));
      expect(ScreenResolver.resolveDetailed(ctx).name, 'SETTINGS');
    });

    testWidgets('a widget with no matching suffix yields UNKNOWN',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PlainWidget()));
      final ctx = tester.element(find.byType(PlainWidget));
      final r = ScreenResolver.resolveDetailed(ctx);
      expect(r.name, 'UNKNOWN');
      expect(r.layer, 0);
    });
  });

  group('layer 4 — rank decides between an ancestor and its descendant', () {
    testWidgets('a component nested inside a screen does not take the name',
        (tester) async {
      // FOUND IN A REAL HOST, not invented. Snapdrop's HomeScreen renders a
      // widget class called DropDownView inline, inside an Expanded. Keeping
      // the deepest match unconditionally made the main screen of that app
      // report DROPDOWN.
      //
      // A descendant now has to rank at least as high as the match above it:
      // Screen beats Page beats View. A View inside a Screen is a component.
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(child: SettingsView()),
        ),
      );
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);

      expect(r.layer, 4);
      expect(r.name, 'HOME');
    });

    testWidgets('a Page inside a Screen is also a component', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(child: CheckoutPage()),
        ),
      );
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);

      expect(r.name, 'HOME');
    });

    testWidgets('an equal-ranked descendant still wins, which is the tab case',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(child: ProfileScreen()),
        ),
      );
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);

      expect(
        r.name,
        'PROFILE',
        reason: 'a shell rendering the selected screen must report the screen',
      );
    });

    testWidgets('a screen inside a lower-ranked host wrapper still wins',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ShellView(child: HomeScreen()),
        ),
      );
      final ctx = tester.element(find.byType(ShellView));
      final r = ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);

      expect(r.name, 'HOME');
    });

    testWidgets(
        'a pushed route outranks the screen underneath it, whatever '
        'its suffix', (tester) async {
      // The route below stays mounted, so both subtrees are walked. A match in
      // a different branch is a different route, not a component, and the last
      // one visited is the one on top of the overlay. Rank must not interfere:
      // a View pushed over a Screen is the screen the tester is looking at.
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: key, home: const HomeScreen()),
      );
      unawaited(
        key.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const DetailsView()),
        ),
      );
      await tester.pumpAndSettle();

      final root = tester.element(find.byType(MaterialApp));
      final r = ScreenResolver.resolveDetailed(
        root,
        searchRoot: root,
      );

      expect(r.name, 'DETAILS');
      expect(r.layer, 4);
    });

    testWidgets('a GuidesterScreen wrapper beats layer 4 entirely',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GuidesterScreen(
            name: 'HOME',
            child: HomeScreen(child: SettingsView()),
          ),
        ),
      );
      final ctx = tester.element(find.byType(SettingsView));
      final r = ScreenResolver.resolveDetailed(ctx, searchRoot: ctx);

      expect(r.layer, 1);
      expect(r.name, 'HOME');
    });
  });

  group('layer 4 must not match Flutter framework widgets', () {
    testWidgets(
        'a screen wrapped in SingleChildScrollView is not SINGLECHILDSCROLL',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SingleChildScrollView(child: PlainWidget()),
        ),
      );
      final ctx = tester.element(find.byType(PlainWidget));
      final r = ScreenResolver.resolveDetailed(ctx);
      expect(r.name, isNot(contains('SINGLECHILDSCROLL')));
      expect(
        r.name,
        'UNKNOWN',
        reason: 'no host screen present, so declining beats a wrong name',
      );
    });

    testWidgets('ListView and PageView do not become screen names',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            children: const [SizedBox(height: 100, child: PlainWidget())],
          ),
        ),
      );
      final ctx = tester.element(find.byType(PlainWidget));
      expect(ScreenResolver.resolveDetailed(ctx).name, 'UNKNOWN');
    });

    // Found on the A015, 25 Sep: every comment filed while Snapdrop showed a
    // showDialog came back DISPLAYFEATURESUB. The dialog route wraps its page
    // in DisplayFeatureSubScreen, a later sibling of the host's HomeScreen
    // with the same rank, so it won.
    testWidgets('an open dialog does not become DISPLAYFEATURESUB',
        (tester) async {
      late BuildContext overlayContext;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            overlayContext = context;
            return child!;
          },
          home: const HomeScreen(),
        ),
      );
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(HomeScreen)),
          builder: (_) =>
              const AlertDialog(content: Text('Allow photo access')),
        ),
      );
      await tester.pumpAndSettle();

      final r = ScreenResolver.resolveDetailed(
        overlayContext,
        searchRoot: overlayContext as Element,
      );
      expect(r.name, 'HOME');
      expect(r.layer, 4);
    });

    // A hand-kept list goes stale the day Flutter adds a widget. This reads
    // the SDK the test runs against and names every public class ending in a
    // screen suffix that the list does not skip.
    test('every Flutter widget ending in Screen, Page or View is skipped', () {
      final root = Platform.environment['FLUTTER_ROOT'];
      if (root == null) {
        markTestSkipped('FLUTTER_ROOT not set; run under `flutter test`');
        return;
      }
      final src = Directory('$root/packages/flutter/lib/src');
      final decl = RegExp(
        r'^(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+'
        r'([A-Z]\w*(?:Screen|Page|View))\b',
        multiLine: true,
      );
      final found = <String>{
        for (final f in src.listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart'))
            for (final m in decl.allMatches(f.readAsStringSync())) m[1]!,
      }
        // Render objects are never an element's widget.
        ..removeWhere((n) => n.startsWith('Render'));

      expect(found, isNotEmpty, reason: 'the scan read no SDK source');
      expect(
        found.difference(ScreenResolver.frameworkTypes),
        isEmpty,
        reason: 'add these to ScreenResolver._frameworkTypes',
      );
    });

    testWidgets('a real screen inside a scroll view still resolves',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SingleChildScrollView(child: HomeScreen()),
        ),
      );
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx);
      expect(r.name, 'HOME');
      expect(r.layer, 4);
    });
  });

  group('layer 3 — MaterialApp.router hosts', () {
    testWidgets('resolves when builder wraps the Router from above',
        (tester) async {
      // MaterialApp.router applies `builder` ABOVE the Router, so an ancestor
      // lookup finds nothing and the Router sits in our child subtree instead.
      // A real host app fell through to the layer 4 heuristic because of this,
      // despite having proper paths like /today.
      late BuildContext overlayContext;
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: routerConfigFor(initialPath: '/today'),
          builder: (context, child) {
            overlayContext = context;
            return child!;
          },
        ),
      );
      await tester.pumpAndSettle();

      final r = ScreenResolver.resolveDetailed(overlayContext);
      expect(r.name, 'TODAY');
      expect(r.layer, 3, reason: 'the Router below must be found');
    });

    testWidgets('with nested Routers, the outer one names the screen',
        (tester) async {
      // The downward search takes the FIRST Router it finds, which is the
      // app-level one. D44 flagged this as unverified against a host whose
      // bottom navigation nests Routers, and left it open.
      //
      // Outer-wins is the behaviour to want, not merely the behaviour we have:
      // the outer Router holds the location the whole app is at, which is what
      // a developer reading a bug report needs. An inner Router driving a
      // sub-flow answers a question nobody asked — /step-2 of what?
      late BuildContext overlayContext;
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: routerConfigFor(
            initialPath: '/library',
            child: MaterialApp.router(
              routerConfig: routerConfigFor(initialPath: '/inner-flow'),
            ),
          ),
          builder: (context, child) {
            overlayContext = context;
            return child!;
          },
        ),
      );
      await tester.pumpAndSettle();

      final r = ScreenResolver.resolveDetailed(overlayContext);
      expect(r.layer, 3);
      expect(
        r.name,
        'LIBRARY',
        reason: 'the app-level location, not /inner-flow',
      );
    });
  });

  group('precedence', () {
    testWidgets('an attached layer 2 beats layer 4', (tester) async {
      final observer = GuidesterRouteObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          initialRoute: '/from-observer',
          routes: {'/from-observer': (_) => const HomeScreen()},
        ),
      );
      final ctx = tester.element(find.byType(HomeScreen));
      final r = ScreenResolver.resolveDetailed(ctx, observer: observer);
      expect(r.layer, 2);
      expect(r.name, 'FROM OBSERVER');
    });

    testWidgets('null context never throws', (tester) async {
      expect(ScreenResolver.resolveDetailed(null).name, 'UNKNOWN');
    });
  });
}
