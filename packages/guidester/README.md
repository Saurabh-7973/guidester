# guidester

**Testers tap anywhere in your app, type what's wrong, and it lands on your dashboard with
a screenshot, the screen name, the device, the build, and the error that caused it.**

![A tester pins a comment on the checkout screen; it lands on the dashboard with the screenshot and screen name.](https://raw.githubusercontent.com/Saurabh-7973/guidester/main/packages/guidester/screenshots/demo.gif)

```dart
void main() {
  Guidester.init(
    apiKey: const String.fromEnvironment('GUIDESTER_KEY'),
    endpoint: const String.fromEnvironment('GUIDESTER_ENDPOINT'),
  );
  runApp(const MyApp());
}

// on your MaterialApp
builder: (context, child) => GuidesterOverlay(child: child!),
// Navigator 1.0 named routes (MaterialApp(routes: ...)) only; a Router app
// (go_router, MaterialApp.router) needs nothing here
navigatorObservers: [Guidester.observer],
```

```bash
flutter pub add guidester
flutter run --dart-define=GUIDESTER_KEY=<your key> \
            --dart-define=GUIDESTER_ENDPOINT=<your ingest URL>
```

That is the whole install. Three lines of Dart, two commands. The endpoint is your own
deployment of the backend in this repository — the package ships no default
([self-hosting](https://github.com/Saurabh-7973/guidester/blob/main/packages/guidester/doc/self-hosting.md)).

**The key is the switch.** A production build passes no `--dart-define`, so the key is
empty, so the overlay returns your widget on the first line of `build()` and no capture or
network path is reachable. Forgetting the define fails safe.

**It does not take over your app and does not touch your navigator.** The overlay sits in
`MaterialApp.builder`, above the `Navigator` but inside the app: no route is ever pushed,
the widget tree is never swapped for a screenshot view, and your app keeps running
underneath. The bug classes that come from doing it the other way — navigation
interference, page offsets, router conflicts, theme corruption — are unreachable here by
construction.

## Documentation

| Page | For |
|---|---|
| [Quickstart](https://github.com/Saurabh-7973/guidester/blob/main/packages/guidester/doc/quickstart.md) | installing and seeing a comment arrive |
| [What gets captured](https://github.com/Saurabh-7973/guidester/blob/main/packages/guidester/doc/what-gets-captured.md) | every field that leaves the device, and the privacy statement |
| [Troubleshooting](https://github.com/Saurabh-7973/guidester/blob/main/packages/guidester/doc/troubleshooting.md) | no bubble, `UNKNOWN` screens, blank screenshots |
| [Self-hosting](https://github.com/Saurabh-7973/guidester/blob/main/packages/guidester/doc/self-hosting.md) | pointing it at your own backend |

## Screen names, whatever your router

The screen tag is the point of the product — a dashboard full of `UNKNOWN` is no product at
all. The resolver has four layers and takes the first that produces something usable:

| Layer | Source | Covers | Reliable |
|---|---|---|---|
| 1 | `Guidester.setScreen()` or a `GuidesterScreen` ancestor | manual override, always wins | yes |
| 2 | `NavigatorObserver` route names | named routes, most GoRouter setups | yes |
| 3 | `Router`'s current URI | GoRouter, auto_route, Beamer — `Router` is Flutter core | yes |
| 4 | a widget type ending in `Screen`/`Page`/`View` | unnamed routes | best-effort |

A layer that resolves to nothing usable **declines** rather than winning with `UNKNOWN`, so
a root route named `/` falls through to the next layer instead of poisoning every report.

**Layers 1 to 3 read strings you wrote — a name, a route, a URI. Layer 4 reads class names,
which is a guess and which the compiler is allowed to take away.** Two consequences worth
knowing before you rely on it:

- **`--obfuscate` removes layer 4 entirely.** It is the recommended setting for a Play
  release, and it renames every Dart class: `HomeScreen` compiles to something like `Dw`,
  no suffix matches, and every screen the heuristic named reports `UNKNOWN` at once.
  Measured on a device, not assumed. The SDK prints this at `init` so it is not a mystery.
  Layers 1 to 3 are unaffected.
- **Nesting is decided by a rule, not by depth.** A match in a different branch wins (a
  pushed route beats the screen mounted underneath it), and a match nested *inside* another
  wins only at equal or higher rank, `Screen` > `Page` > `View`. So a `DropDownView`
  rendered inside a `HomeScreen` is read as a component and the screen keeps its name — but
  a screen called `CartView` rendering a `SummaryScreen` will report `SUMMARY`.

If either matters to you, name the screen: `GuidesterScreen(name: 'CHECKOUT', child: ...)`
is layer 1 and cannot be wrong.

There is no dependency on `go_router`, `auto_route` or `beamer`. Layer 3 reads Flutter's own
`Router`, which every declarative router builds on.

Stuck on `UNKNOWN`? `Guidester.debugResolveScreen(context)` tells you the name and which
layer produced it.

## Off in production, by construction

There is no flag to remember. `Guidester.isEnabled` is false whenever the api key is empty,
and `GuidesterOverlay.build` checks it on its first line, so a build that passes no
`--dart-define=GUIDESTER_KEY` has no bubble, no capture path and no network call.

```bash
# what testers get
flutter build apk --dart-define=GUIDESTER_KEY=<key>

# what the public gets
flutter build appbundle
```

Two overrides exist for people who hardcode a key: `Guidester.init(enabled: false)`, and
`--dart-define=GUIDESTER=false`, which wins over everything.

Be honest with yourself about what this is not: the dependency is still compiled into the
binary. It never runs. If you need it absent, use a separate entrypoint that does not
import it.

**Test builds only.** Screenshots from production capture other people's personal data.
Wait for redaction support before shipping this to a live listing.

## What lands on the dashboard

Real columns: screen name, tap position, screenshot, tester name, device model, OS version,
app version. Everything else rides along as JSON — route breadcrumb, which resolver layer
fired, manufacturer, emulator flag, screen size, pixel ratio, **text scale factor**,
**platform brightness**, orientation, locale, timezone offset.

Those last three close most bug reports on their own: a large font scale, dark mode, or an
emulator. There is no reply thread in this version — the device context is the answer to
"which device were you on?" before you have to ask.

## The stack that caused it

When Guidester is enabled it chains `FlutterError.onError` and
`PlatformDispatcher.instance.onError`, keeps the **last three errors of the session**, and
sends them with the next comment: the exception, up to 24 stack frames, the Flutter library
that reported it, and the route it happened on. The dashboard shows the first frame outside
Flutter — `package:your_app/screens/home.dart:42:9` — which is the line you actually open.

Nothing is swallowed. Both handlers call whatever was installed before them, and the
platform handler still reports the error as unhandled, so a crash still crashes and
Crashlytics still sees what it saw. A production build installs neither handler.

What it does not catch: an exception your own code catches and swallows, and errors thrown
in a zone Guidester never sees.

**An exception message can quote your app's own data.** `Invalid argument:
user@example.com` is an ordinary Dart error, and nothing here redacts it. That is the same
argument the screenshot already makes about who a test build should reach.

## The launch ping

When the overlay mounts, the SDK posts one small request — no comment, no screenshot — that
records the key's last-used time and the device that reported. That is what the dashboard's
onboarding screen reads to tell you the install worked, instead of asking you whether it
did.

It fires from the overlay rather than from `init` on purpose. The install is two changes,
and an app with the `init` call but no `GuidesterOverlay` cannot produce a single comment;
saying "connected" about that app would be the exact false pass the check exists to remove.

## Behaviour worth knowing

- Screenshot capture is bounded. If it stalls, the comment still sends, without an image.
- Context gathering is bounded. A silent platform channel never blocks a send.
- The send button is guarded, so a double-tap cannot ship two copies of the same comment.
- A send that fails for lack of a connection is saved on the phone and sent later (see
  Limitations). A send the server refuses keeps your tester's text and shows why.
- After a successful send the overlay returns to idle, so the tester can navigate to the
  next screen. Another comment is one tap on the bubble.
- Bubble, mode bar, pin and composer all carry `Semantics` labels.

## Limitations

- Platform views are blank in screenshots: maps, webviews, camera preview, some video
  players. A Flutter engine limitation, not something a package can fix.
- `showDialog` with `useRootNavigator: true` renders above the overlay. Use
  `useRootNavigator: false`.
- A comment sent without a connection waits on the phone (at most 20, for 14 days) and
  goes on the next launch, return to the app, or retry. On the web it is not queued.
- The API key is extractable from a shipped APK. The backend limits each key (30 comments
  a minute); a comment over the limit waits in the offline queue and goes later.
- Unnamed routes fall back to a class-name heuristic (layer 4) and can be wrong. It is
  best-effort by design, and **an obfuscated build has no layer 4 at all** — every screen it
  would have named reports `UNKNOWN`. Layers 1 to 3 survive obfuscation because they read
  strings rather than class names.
- v0 targets Android and iOS.
- Error capture starts at `Guidester.init`, so anything thrown before that call is missed.

## Example

`example/` runs the same SDK under two routing styles in one app — named `Navigator` routes
and GoRouter — and prints the resolved name and layer on every screen.

## Licence

MIT.
