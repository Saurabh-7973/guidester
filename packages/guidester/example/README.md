# guidester example

**Try it without installing anything:** [the example in your browser](https://saurabh-7973.github.io/guidester/).
Tap the bubble, pin something, send it, and watch it land on the board beside the phone.

This app exists to show one thing: the screen tag is right whatever your router. Every
screen prints what the resolver names it and which layer produced the name.

| Screen | Router | Resolves to | Layer |
|---|---|---|---|
| `/home`, `/checkout` | `Navigator.pushNamed` | `HOME`, `CHECKOUT` | 2, named route |
| *Push ProfileScreen*, from `/unnamed` | a route with no name | `PROFILE` | 4, class-name fallback |
| `/settings/profile` | GoRouter | `SETTINGS/PROFILE` | 3, the Router's URI |

*Switch router style* flips the whole app between the two, with no change to how
Guidester is installed. *Throw an error, then comment* shows the error arriving with the
comment it caused.

## The whole integration

```dart
void main() {
  Guidester.init(
    apiKey: const String.fromEnvironment('GUIDESTER_KEY'),
    endpoint: const String.fromEnvironment('GUIDESTER_ENDPOINT'),
  );
  runApp(const ExampleApp());
}

MaterialApp(
  builder: (context, child) => GuidesterOverlay(child: child!),
  navigatorObservers: [Guidester.observer], // named routes only
  // ...
)
```

## Run it against your own backend

Set up the backend first ([quick start](https://github.com/Saurabh-7973/guidester/blob/main/packages/guidester/README.md#quick-start)), then:

```bash
flutter run --dart-define=GUIDESTER_KEY=<your key> \
            --dart-define=GUIDESTER_ENDPOINT=https://<your-project-ref>.supabase.co/functions/v1/ingest
```

Without the defines the app runs normally and Guidester stays off, which is exactly what
your public release does.

`lib/web_demo.dart` is the in-browser version: the same app in a phone frame, with a
board that shows each comment instead of sending it anywhere.
