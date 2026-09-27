# guidester

**Testers tap anywhere in your app, type what's wrong, and it lands on your dashboard with
a screenshot, the screen name, the device, the build, and the error that caused it.**

![A tester pins a comment on the checkout screen; it lands on the dashboard with the screenshot and screen name.](https://raw.githubusercontent.com/Saurabh-7973/guidester/main/packages/guidester/screenshots/demo.gif)

[![Try it in your browser](https://img.shields.io/badge/Try_it-in_your_browser-2F59ED?style=for-the-badge)](https://saurabh-7973.github.io/guidester/)

Tap the bubble, pin something, send it, and watch it land on the board. It runs the
real package in your browser; nothing you type leaves it.

## How it works

For your testers, it is four taps:

1. **Tap the blue bubble** in the corner of the test build.
2. **Tap the spot** that is wrong. A pin drops there.
3. **Type what's wrong**, pick how bad it is (Blocked, Annoying, Cosmetic), and send.
4. That's it. The app keeps running underneath the whole time.

On your dashboard the comment arrives with a screenshot and the pin on it, the screen
name, the device, the build, and the last errors the app threw. When you mark it fixed,
the tester's bubble shows a badge on their next launch, and they answer *Works now* or
*Still broken* (with a fresh screenshot).

Your testers' screenshots go to **your own** Supabase project. There is no Guidester
server in between.

## Quick start

About 15 minutes, once. You need a Flutter app, a free
[Supabase](https://supabase.com) account, and the
[Supabase CLI](https://supabase.com/docs/guides/cli).

### 1. Set up your backend (one command)

Create an empty project at [supabase.com/dashboard](https://supabase.com/dashboard). Note
its **project ref** (the 20 letters in its URL) and the **database password** you chose.
Then:

```bash
supabase login
git clone https://github.com/Saurabh-7973/guidester.git
cd guidester
./supabase/setup.sh --project-ref <your-project-ref>
```

It sets up the database, deploys the function your app sends to, checks it answers, and
builds your dashboard. It asks for the database password rather than taking it on the
command line. At the end it prints your **endpoint**:

```
https://<your-project-ref>.supabase.co/functions/v1/ingest
```

### 2. Open your dashboard and create a project

```bash
cd apps/dashboard/build/web && python3 -m http.server 8765
```

Open `http://localhost:8765` in your browser, sign up and confirm your email, then create a project. The
last onboarding step shows your **key** and endpoint, ready to paste.

> In Supabase, set **Authentication → URL Configuration → Site URL** to wherever you
> serve the dashboard, so the confirmation email opens it. To share the dashboard with
> your team, upload `build/web` to any static host.

### 3. Add the package

```bash
flutter pub add guidester
```

### 4. Add two things to your app

In `main.dart`:

```dart
import 'package:guidester/guidester.dart';

void main() {
  Guidester.init(
    apiKey: const String.fromEnvironment('GUIDESTER_KEY'),
    endpoint: const String.fromEnvironment('GUIDESTER_ENDPOINT'),
  );
  runApp(const MyApp());
}
```

And on your `MaterialApp` (or `MaterialApp.router`):

```dart
MaterialApp(
  builder: (context, child) => GuidesterOverlay(child: child!),
  // Only if you use named routes with Navigator.pushNamed.
  // go_router, auto_route and other Router apps need nothing here.
  navigatorObservers: [Guidester.observer],
  // ...
)
```

**Both are needed.** `init` alone cannot file a comment: the overlay is what draws the
bubble and takes the screenshot. If you forget it, the console says so.

### 5. Run it with your key

```bash
flutter run --dart-define=GUIDESTER_KEY=<your key> \
            --dart-define=GUIDESTER_ENDPOINT=<your endpoint>
```

Or keep both in a git-ignored file, `guidester.json`:

```json
{"GUIDESTER_KEY": "<your key>", "GUIDESTER_ENDPOINT": "<your endpoint>"}
```

```bash
flutter run --dart-define-from-file=guidester.json
```

### 6. Check it works

- **The dashboard says so.** Onboarding flips to *Connected — Pixel 7, Android 15* (your
  device) within seconds of the app starting. That means the overlay is really in your
  app, not just that the key was pasted.
- **Send one.** Tap the bubble, tap anywhere, type, send. You see *Comment sent*, and the
  comment is on your board with its screenshot.
- **The console tells you the screen name** each time you place a pin:
  `[guidester] screen: HOME (layer 2)`. If it says `UNKNOWN`, see
  [screen names](#screen-names-whatever-your-router).

Nothing happening? Every misconfiguration prints one `[guidester]` line in the console
saying what to fix. The
[troubleshooting guide](https://github.com/Saurabh-7973/guidester/blob/main/packages/guidester/doc/troubleshooting.md)
covers each one.

### 7. Give it to your testers

```bash
flutter build apk --dart-define-from-file=guidester.json
```

Share that APK (or upload it to an internal testing track). Your public release is built
**without** the defines, so Guidester is switched off in it: no bubble, no capture, no
network call.

> **Android release builds need the internet permission.** Flutter adds it to debug builds
> only. If your app makes no other network calls, add
> `<uses-permission android:name="android.permission.INTERNET"/>` to
> `android/app/src/main/AndroidManifest.xml`.

## Why it is safe to add

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
- Android and iOS are the targets, and both are checked on a device before a release
  (`example/integration_test/device_test.dart`). The web works too (the demo above runs
  on it), without the offline queue.
- Error capture starts at `Guidester.init`, so anything thrown before that call is missed.

## Example

`example/` runs the same SDK under two routing styles in one app — named `Navigator` routes
and GoRouter — and prints the resolved name and layer on every screen. The same app runs
[in your browser](https://saurabh-7973.github.io/guidester/), with a board beside it.

## Licence

MIT.
