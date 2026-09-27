# Quickstart

About 15 minutes, once. You need a Flutter app, a free
[Supabase](https://supabase.com) account, and the
[Supabase CLI](https://supabase.com/docs/guides/cli).

## 1. Set up your backend (one command)

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

## 2. Open your dashboard and create a project

```bash
cd apps/dashboard/build/web && python3 -m http.server 8765
```

Open `http://localhost:8765` in your browser, sign up and confirm your email, then create a project. The
last onboarding step shows your **key** and endpoint, ready to paste.

> In Supabase, set **Authentication → URL Configuration → Site URL** to wherever you
> serve the dashboard, so the confirmation email opens it. To share the dashboard with
> your team, upload `build/web` to any static host.

## 3. Add the package

```bash
flutter pub add guidester
```

## 4. Add two things to your app

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

## 5. Run it with your key

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

## 6. Check it works

- **The dashboard says so.** Onboarding flips to *Connected — Pixel 7, Android 15* (your
  device) within seconds of the app starting. That means the overlay is really in your
  app, not just that the key was pasted.
- **Send one.** Tap the bubble, tap anywhere, type, send. You see *Comment sent*, and the
  comment is on your board with its screenshot.
- **The console tells you the screen name** each time you place a pin:
  `[guidester] screen: HOME (layer 2)`. If it says `UNKNOWN`, see
  [troubleshooting](troubleshooting.md#every-comment-says-unknown).

Nothing happening? Every misconfiguration prints one `[guidester]` line in the console
saying what to fix. The
[troubleshooting guide](troubleshooting.md)
covers each one.

## 7. Give it to your testers

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

## Optional: name the environment

```bash
--dart-define=GUIDESTER_ENV=uat
```

Every comment then carries it. A bug that reproduces in UAT and not in production is a
different bug, and this is the field that lets you filter for it instead of asking.
