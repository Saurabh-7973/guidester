## 0.5.8

- The package now has a homepage, https://saurabhupadhyay.in/guidester, and a verified
  publisher, saurabhupadhyay.in.

## 0.5.7

- **Draw on the screenshot.** In the composer, *Mark up screenshot* opens the capture full
  screen with the pin shown; the tester draws with a finger (Undo, Clear), and the marks
  are burned into the image that is sent. The capture as taken is kept, so drawing again
  starts from it. A failed burn-in sends the plain screenshot; marking never loses a
  report. Back from the drawing returns to the composer. Checked on the iOS simulator: the
  mark is in the pixels the device sends.
- **What gets captured is exact.** The page now lists the launch ping's tester id, the
  offline queue that stores a comment on the device and sends it later, the answers to
  "please check this fix", and what a connected Slack, Discord or Teams channel receives.
- Quick start: open the confirmation email on the computer running the dashboard. The
  self-hosting guide has the manual commands and what `setup.sh` needs on Windows.
- README: which platforms are checked on a device, and the web demo linked from the Example
  section.

## 0.5.6

- **Web and WebAssembly are supported platforms.** The package no longer imports `dart:io`
  directly, and on the web it reads the app version from `version.json` and the device
  from the browser instead of `package_info_plus` and `device_info_plus`, which pulled
  `dart:io` into web builds. Nothing changes on Android, iOS or desktop.
- **On the web, the OS field is the browser platform** ("Web · MacIntel"), not the
  browser's whole user-agent string.
- **Verified on devices:** a new end-to-end test (`example/integration_test/device_test.dart`)
  files a comment with a real screenshot on the iOS simulator and the Android emulator.
- API documentation for the public members that had none, and an example README that says
  what the example proves.
- The quick start's local dashboard address is no longer a link (pub.dev scored it as
  insecure).

## 0.5.5

- **Try it in your browser:** https://saurabh-7973.github.io/guidester/ runs the example
  app with the real package, and a board beside it that shows each comment as your
  dashboard would. Linked from the top of this page.
- **A step-by-step quick start**, from backend to a comment on your board, with a step for
  checking it worked and one for handing the build to testers.
- **A draft closed with Back says where it was written.** Typing on one screen, pressing
  Back, and pinning on another reopened the draft with no word that it came from
  elsewhere. It now shows "Unsent comment from CHECKOUT", as a relaunch already did. The
  comment is still filed under the screen it is pinned on when sent.

## 0.5.4

Documentation only; no code changes.

- The source is public at https://github.com/Saurabh-7973/guidester, so the repository,
  issues and documentation links on this page resolve.
- The four documentation links were dropped by pub.dev, because the package lives in a
  subfolder of the repository. They are full links now, and `repository` names the
  subfolder.
- The demo sits at the top of the README.

## 0.5.3

Found recording the demo on an emulator, 27 Sep.

- **The app underneath no longer takes taps while the composer is open.** A tap above
  the sheet used to reach the app: it could navigate to another screen while the
  composer kept the first screen's name and screenshot, so the comment filed against a
  screen the tester had left. A tap there now only puts the keyboard away.
- **No stray back arrow.** While the sheet was up, the app's own AppBar showed a back
  arrow on a root screen, because the Back handling added in 0.5.0 read as "there is
  somewhere to go back to".
- **A clearer log for a missing INTERNET permission.** A release Android build without
  `android.permission.INTERNET` fails as a host lookup on a device that is online, and
  the log sent you to check a correct endpoint. It now names the permission too.
- A 10-second demo on the pub.dev page (the `screenshots` field): a comment pinned on a
  screen, and the same comment on the dashboard.
- The example app's release build declares INTERNET, and its `/unnamed` page states the
  layer it actually resolves at.

## 0.5.2

Documentation only; no code changes.

- The self-hosting guide said no rate limiting exists. Each key has been limited since
  migration 0012 (30 comments, 120 launches, 60 verdicts a minute, `429 rate_limited`
  with `Retry-After`); the guide now says so.
- The guide leads with `./supabase/setup.sh`, which sets up your own backend and
  dashboard in one command.

## 0.5.1

Documentation only; no code changes.

- The package description no longer says "hosted": there is no hosted service, and the
  endpoint is your own deployment (D71).
- The README said the overlay stays armed after a send. It returns to idle, so the tester
  can reach the next screen; this changed before 0.5.0 and the README was not updated.
- The README said every failed send keeps the text on screen. A send that fails for lack
  of a connection is now queued on the phone instead; only a refusal keeps the text.

## 0.5.0

**Breaking: `endpoint` is required, and the package ships no backend URL.**

Why: this is a security decision, not a refactor. A self-hosted package must not default
to someone else's server. Until now an install that forgot the endpoint sent its testers'
screenshots and comments to the package author's Supabase project, and publishing would
have made that ingest endpoint findable by anyone reading the package source (D69, D71).

- `Guidester.init({required String apiKey, required String endpoint, bool? enabled})`.
  `Guidester.hostedEndpoint` is gone. Pass `const String.fromEnvironment('GUIDESTER_ENDPOINT')`
  and `--dart-define=GUIDESTER_ENDPOINT=<your ingest URL>`.
- An empty endpoint with a key present disables the SDK and prints
  `[guidester] disabled — GUIDESTER_ENDPOINT is empty`. It used to fall back to the author's
  project; there is no hosted offer for it to fall back to.
- A test scans `lib/` for URL literals, so a default cannot come back unnoticed.
- **An unsent comment survives a force-stop.** The draft is saved as it is typed and handed
  back on the next launch, with the screen it was written on.
- **A wrong endpoint says so, at launch:** one `[guidester]` line naming the URL and status,
  from the launch ping. Testers are told the build is misconfigured, or that the server was
  not reached, never that their network is down when it is not.
- **Android Back closes the sheet**, not the app's screen underneath it. The draft is kept.
- **A comment sent offline is not lost.** When a send fails because the network or the
  server is down, the comment and its screenshot are saved on the phone, the composer
  closes with "No connection. Saved", and it goes on the next launch, when the app comes
  back to the foreground, after any comment that does go through, and on a backoff
  (15 s up to 5 min) while the app is open. Refusals (bad key, too long) are not queued
  and show as before. Every comment carries a `client_id`, so a retry of one that did
  arrive is stored once: **deploy migration 0011 and the new ingest function** with this
  version. Adds `path_provider`; queued comments are files, not preferences.

## 0.4.0

**The loop closes.** A developer marking a report fixed can now reach the tester who filed
it, and the tester can answer with evidence — inside the app, on the build in their hand.

- **The launch ping carries `tester_id` and reads the response.** The return leg rides the
  request that already exists rather than a new endpoint: the ping is already
  authenticated, and a launch is exactly when a tester can act on "please re-check this".
  `ApiClient.ping` now answers with a `PingResult` carrying `PendingRetest` rows. An older
  backend, an unparseable body, or a rejected key all mean no retests and never an
  exception on the launch path.
- **A count on the bubble** when something is waiting. It costs no notification permission,
  no login and no link. The badge is its own hit target: tapping the bubble still arms
  comment mode, because the main action must not depend on what the server said.
- **Two buttons per item — Works now / Still broken.** Both write `tester_verdict` through
  the same ingest function, which checks twice over that the row belongs to this key's
  project *and* carries this tester's id. A refused answer keeps the item on the list.
- **"Still broken" arms a fresh capture**, with the report's own words already in the
  draft. That is why this lives in the app instead of behind a link: the answer "no" can
  carry a new screenshot, the current build and the current device state. A browser link
  can only send the word "no".
- The tester-id read runs alongside the device lookup on a 500ms budget of its own, so a
  shared_preferences store that never answers costs the return leg and never the ping.

**Diagnostic 6: an obfuscated build says so, at `init`.** `flutter build --obfuscate` renames every
Dart class, so layer 4 has nothing left to read and every screen it named reports `UNKNOWN`
at once. Measured on hardware, not assumed: `HomeScreen` comes back as `Dw`. Layers 1 to 3
are unaffected, because route names and router URIs are strings. The SDK now prints this
once, at `Guidester.init` rather than at the first failed resolve — a developer who never
files a comment never resolves a screen, and would otherwise learn this from a dashboard
full of `UNKNOWN` with nothing anywhere saying why. The README now states plainly that
layers 1 to 3 are the reliable tiers and layer 4 is best-effort.

**Layer 4 no longer lets a component outrank the screen it sits inside.** A `View` rendered
inside a `Screen` is a piece of that screen, so `HomeScreen` rendering a `DropDownView`
inline reports `HOME` — it used to report `DROPDOWN`. A match in a different branch still
always wins, so a pushed route names the screen whatever its suffix. Found in a real host
app.

## 0.3.0

**The install is two lines. It was four.** This is the product surface for a package a
developer decides about in thirty seconds, and three of the four things it asked for were
avoidable.

- `endpoint` is now optional and defaults to the hosted backend. Nobody should paste a
  Supabase URL to try a package. Pass it to self-host; an empty string falls back rather
  than disabling, so a missing dart-define cannot silently kill your build.
- `enabled` is now optional. **The api key is the kill switch.** A production build passes
  no `--dart-define=GUIDESTER_KEY`, so the key is empty, so `isEnabled` is false and the
  overlay returns your widget on the first line of `build()`. `enabled:` remains as an
  override for anyone hardcoding a key, and `--dart-define=GUIDESTER=false` now turns
  everything off regardless — read as a string, because `bool.fromEnvironment` cannot tell
  "not passed" from "passed as false", and that distinction matters once the key arms it.
- `navigatorObservers` is out of the documented install. Layer 3 reads Flutter's own
  `Router` and answers for every router-based app. The observer is now documented as the
  Navigator 1.0 note it always was.

**Five console diagnostics**, because silence is the worst possible answer to a
misconfiguration and four of these produce the same visible symptom:

- an empty key, which is also what a correct production build looks like
- `init()` called with no `GuidesterOverlay` ever mounted — the failure that looks most
  like a broken package, since everything is configured correctly and no comment can ever
  be filed
- a screen that resolved to `UNKNOWN` with no route name and no `Router`, naming the
  observer as the fix, printed once a session rather than once a tap
- a key rejected with 401, distinguishing revoked from invalid
- a capture containing a platform view, which renders blank for engine reasons rather than
  app reasons

**Docs.** README rewritten to open with the snippet and the install commands. Four pages in
`doc/`: quickstart, what gets captured, troubleshooting, self-hosting. Four get maintained;
twelve rot.

Nothing is removed and no call site breaks: the old four-argument form still compiles and
behaves as before.

## 0.2.0

- Comments now carry the last three errors of the session: exception, trimmed stack, the
  Flutter library that reported it, and the route it happened on. Chained onto
  `FlutterError.onError` and `PlatformDispatcher.onError`, and installed only when the SDK
  is enabled. Nothing is swallowed — both handlers still call whatever was there before.
- The overlay announces its first launch to the backend, so a dashboard can state that an
  install worked rather than asking.
- A revoked project key now reports itself as revoked rather than as invalid, so a tester
  is told to install a newer build.
- Errors and the launch ping are both declared in PRIVACY.md. An exception message can
  quote your app's own data and nothing redacts it.

## 0.1.0

- Initial release.
- Persistent bubble overlay: tap anywhere on any live screen to pin a comment.
- Router-agnostic screen resolution (four layers, no router dependency).
- Screenshot capture excluding overlay chrome, capped at 720 logical px.
- Device, display and locale context captured at tap time.
- Off by default; opt in per build.
