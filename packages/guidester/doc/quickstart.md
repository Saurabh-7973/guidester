# Quickstart

From nothing to a comment on your dashboard.

## 1. Get a key

Create a project at the Guidester dashboard. Onboarding shows the key on step two, and it
is also in Settings, where you can rotate or revoke it later.

The key is not a secret in the strict sense. It ships inside your test build and anyone
with the APK can extract it — that is by design, and it is why it only ever grants *write*
access to one project, and why revoking it is two clicks.

## 2. Add the package

```bash
flutter pub add guidester
```

## 3. Three lines

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

```dart
MaterialApp(
  builder: (context, child) => GuidesterOverlay(child: child!),
  // ...
)
```

`MaterialApp.router` works exactly the same way — `builder` is in both.

**Both changes are required.** `init` on its own configures an SDK that can never file a
comment, because the overlay is what draws the bubble and captures the screen. If you make
only the first change, the SDK says so in the console after five seconds.

## 4. Run a test build

```bash
flutter run --dart-define=GUIDESTER_KEY=<your key>
```

A blue bubble appears in the corner. Tap it, tap anywhere on the screen, type, send.

## 5. Watch it arrive

The dashboard's onboarding waits for your first launch and moves on by itself when the SDK
reports in. It reads a ping the overlay sends when it mounts, so "connected" means the
overlay is really in your tree — not that you pasted a key correctly.

## Optional: Navigator 1.0 named routes

If your app uses `Navigator.pushNamed` rather than a `Router`, add the observer so screen
names resolve from your route names:

```dart
MaterialApp(
  navigatorObservers: [Guidester.observer],
  builder: (context, child) => GuidesterOverlay(child: child!),
)
```

Router-based apps — go_router, auto_route, Beamer — need nothing. See
[troubleshooting](troubleshooting.md) if screens report `UNKNOWN`.

## Optional: name the environment

```bash
--dart-define=GUIDESTER_ENV=uat
```

Every comment then carries it. A bug that reproduces in UAT and not in production is a
different bug, and this is the field that lets you filter for it instead of asking.
