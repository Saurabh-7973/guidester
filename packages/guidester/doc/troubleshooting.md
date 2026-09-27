# Troubleshooting

The SDK prints a `[guidester]` line for each of these. If you are seeing a symptom and no
line, that itself is information — check that you are running a debug build.

## No bubble appears

**Most likely: the define is not being passed.**

```
[guidester] disabled — GUIDESTER_KEY is empty. Pass
--dart-define=GUIDESTER_KEY=<your key> to a test build.
```

The key is the switch. No key, no bubble, and that is the same mechanism that keeps
production builds inert — so this message is also what a correct production build would
print if anyone were watching.

## No bubble, and the key is definitely set

**The overlay is not in your tree.**

```
[guidester] init() was called but GuidesterOverlay was never mounted, so no
comment can be filed.
```

The install is two changes, not one. Add:

```dart
builder: (context, child) => GuidesterOverlay(child: child!),
```

This is the failure that looks most like a broken package, because the configuration is
correct, the key is valid and the backend is reachable — and not one comment can ever be
filed.

## Every comment says UNKNOWN

**A Navigator 1.0 app with no observer attached.**

```
[guidester] no route name and no Router found, so this screen reports UNKNOWN.
```

Add `Guidester.observer` to `navigatorObservers`. If your app is router-based this should
not happen — layer 3 reads Flutter's own `Router` and answers for go_router, auto_route and
Beamer alike.

To see which layer answered on any screen:

```dart
Guidester.debugResolveScreen(context)  // ScreenResolution(CHECKOUT, layer 3)
```

Or place a pin and read the console. Every comment prints the tag it resolved to
and the layer that produced it, which is how to walk a whole app in one pass:

```
[guidester] screen: CHECKOUT (layer 3)
```

**A class whose name does not end in `Screen`, `Page` or `View` cannot be found
by layer 4 at all.** `class SendFile` in `send_file_screen.dart` reports
`UNKNOWN` — the file name is not readable at runtime, and guessing from anything
less reliable than the class name would send you to the wrong file. Wrap it:

```dart
GuidesterScreen(name: 'SEND FILE', child: ...)
```

That is the documented answer for this case, not a workaround.

Layer 4 is the widget-class heuristic and it is the one to be suspicious of. It searches
downward from the overlay and picks a widget whose type ends in `Screen`, `Page` or `View`,
by two rules:

- A match in a **different branch** always wins, because the branch visited last is the
  route on top. A pushed `DetailsView` beats the `HomeScreen` mounted underneath it.
- A match **inside** another only wins if its suffix ranks at least as high, `Screen` >
  `Page` > `View`. A `DropDownView` rendered inside a `HomeScreen` is a component, and the
  screen keeps its name. An equal rank still wins, so a shell `HomeScreen` rendering the
  selected `ProfileScreen` reports `PROFILE`.

It can still be wrong: a screen named `CartView` that renders a `SummaryScreen` component
reports `SUMMARY`. **A wrong screen name is worse than `UNKNOWN`** — `UNKNOWN` tells you the
resolver failed; a wrong one sends you to the wrong file. Fix it with
`GuidesterScreen(name: ...)` or `Guidester.setScreen()`.

**An obfuscated build has no layer 4 at all.** `flutter build --obfuscate` renames every
Dart class, so `HomeScreen` becomes something like `Dw`, no suffix matches, and every screen
that relied on the heuristic reports `UNKNOWN` at once:

```
[guidester] this build is obfuscated, so the widget-class heuristic (layer 4) cannot
name screens and they report UNKNOWN. Route names and Router URIs still work — layers
1 to 3 are unaffected.
```

Layers 1 to 3 survive obfuscation: manual names, route names and router URIs are strings,
not class names. Measured on hardware, not assumed — see D67.

## Comments never arrive

**The key was rotated, revoked, or mistyped.**

```
[guidester] key rejected (401 key_revoked). This build's key was rotated or
revoked — install a newer build.
```

`invalid_key` and `key_revoked` are different sentences on purpose. Revoked means the build
in your hand is stale, and reinstalling fixes it. Invalid means the define never matched a
real key.

Rotating a key invalidates every installed build, so rotate *before* you cut a release to
testers, never during a test.

**It works in debug and not in release (Android).**

```
[guidester] https://<ref>.supabase.co/functions/v1/ingest could not be reached (host lookup failed).
[guidester] On Android, a release build also needs <uses-permission android:name="android.permission.INTERNET"/> ...
```

Flutter adds `INTERNET` to the debug and profile manifests only. If your app makes no
other network calls, its main manifest may never have declared it, and a release build
cannot reach anything. Add it to `android/app/src/main/AndroidManifest.xml`. The tester
sees "No connection. Saved"; the comments wait in the offline queue and go once a build
with the permission is installed.

## The screenshot has a blank rectangle

```
[guidester] capture contained 1 platform view (RenderAndroidView), which
rendered blank.
```

Maps, webviews, camera previews and video are composited by the platform, not drawn by
Flutter, so Flutter cannot read them back. This is an engine limitation and every capture
package has it. The overlay detects those regions and warns the tester on the composer, so
they describe what they saw instead of assuming you can see it.

## The overlay is drawn over by a dialog

Use `showDialog(useRootNavigator: false)`. With the root navigator the dialog is inserted
above everything including the overlay.

## Nothing at all in the console

The diagnostics are `debugPrint`, so they are debug-build only. In profile or release you
get silence by design.
