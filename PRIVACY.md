# Privacy — what Guidester collects, and what you must declare

Guidester uploads screenshots and device identifiers off-device. The three
requirements below are non-negotiable. Two are code and
are enforced by `packages/guidester/test/privacy_gate_test.dart`. The third is
yours, in the Play Console, and no test can do it for you.

**This is not legal advice.** Get the policy reviewed before any production use.

---

## 1. Off by default — done, and pinned by a test

**Changed in SDK 0.3.0. Read this even if you knew the old rule.**

The gate used to be two facts: a `GUIDESTER` dart-define *and* a non-empty api
key. It is now one. **The key is the switch.** `Guidester.isEnabled` is false
whenever the key is empty, and `GuidesterOverlay.build` checks it on line one, so
a build that passes no `--dart-define=GUIDESTER_KEY` has no bubble, no capture
path and no network call. A host that *forgets* fails safe, exactly as before.

```bash
# The build testers receive
flutter build apk --dart-define=GUIDESTER_KEY=<project api key>

# The build the public receives
flutter build appbundle          # no key; Guidester never runs
```

**What this trades away, stated plainly.** Two independent switches became one, so
a key that reaches a release build by accident — a CI variable, a hardcoded
string, a copied launch configuration — now arms the SDK where before it would
still have been inert. Two answers to that:

- `--dart-define=GUIDESTER=false` turns everything off regardless of the key, and
  it is read as a string rather than a bool so that "not passed" and "passed as
  false" stay distinguishable.
- If you need the code *absent* rather than inert, use a separate entrypoint that
  never imports the package, so tree shaking drops it. That is now the stronger
  option, not a belt-and-braces extra.

The privacy gate test asserts both halves: an empty key cannot be enabled, and a
key alone is enough.

**Be honest in your README:** the dependency is still compiled into the binary.
It is inert, not absent.

---

## 2. Play Data safety — yours to file, on the build that ships to testers

Declare these three categories as **collected** and **transferred off-device**,
purpose *app functionality*:

| Category | What Guidester actually sends | Where it comes from |
|---|---|---|
| Photos and videos | One PNG screenshot of the current screen, per comment. Overlay chrome is excluded; the host app is not. | `overlay.dart`, `_capture()` |
| Device or other IDs | A random per-install id (`guidester.tester_id`), plus device model and OS version, sent with each comment and with the launch ping when the app starts. Not an advertising id, not a hardware id. | `tester_identity.dart`, `capture_context.dart` |
| App activity | The comment text, the resolved screen name, the tap coordinates, the impact, app version, text scale, brightness, orientation, locale, route breadcrumb. | `capture_context.dart` |
| App activity — crash and error data | The last three errors the app threw during the session: the exception text, up to 24 stack frames, the Flutter library that reported it, and the route it happened on. Sent with a comment, never on its own. | `error_recorder.dart` |

Also true, and worth stating plainly in the listing:

- The tester types their own name once. It is device-local and is not an account.
- **A comment sent without a connection is stored on the device** (text, screenshot
  and context, in the app's own storage) and sent automatically when the network is
  back: at most 20, for at most 14 days, deleted once sent.
- **An exception message can quote your app's own data.** `Invalid argument:
  user@example.com` is an ordinary Dart error, and the SDK cannot tell that
  string from any other. Nothing redacts it. If a screen handles data you would
  not put in a bug report, that is an argument against a test build of it
  reaching people outside your team — the same argument the screenshot already
  makes.
- Data is **not** sold, and is not shared with third parties beyond the Supabase
  project you control, with one exception you switch on yourself: if an owner or
  admin connects a Slack, Discord or Microsoft Teams channel (Settings →
  Notifications), each new comment's text, screen name, impact, tester name,
  device, OS and build are posted to that channel. Screenshots, tester ids and
  device context are never sent. Remove the channel to stop it.
- Screenshots live in a **private** bucket and are read only through short-lived
  signed URLs.
- Deletion is supported: one comment, or everything from one tester (see §4).

Add a paragraph to the app's privacy policy covering the test build. A draft is
in §5 below — have it reviewed.

**Read the host app's existing policy before you add to it.** Adding a paragraph
is the easy half; the other half is finding the sentence already there that your
test build makes false. A policy that opens with *"your data stays on your
device — we don't send it to a server we can read"* is still true of the public
release and stops being true for anyone on the tester build, and no amount of
appended text fixes a contradiction earlier on the same page. Search the policy for *on your device*,
*never leaves*, *we cannot see*, *no screenshots* and *not transmitted* before
you write a word.

---

## 3. Tester consent line — done

The name prompt carries it verbatim, before the tester's first comment ever
leaves the device, not behind a link and not collapsed:

> Your feedback is sent with a screenshot of this screen and your device details.

---

## 4. Deletion — the request you will actually receive

A tester screenshots a screen carrying their own real data and asks you to remove
it. Under the DPDP Act that request is not optional and, for the test build, you
are the data fiduciary.

Two paths, both in the dashboard's comment detail, both behind a confirmation:

- **Delete comment** — the row and its screenshot object.
- **Delete everything from &lt;tester&gt;** — every comment and screenshot from that
  `tester_id`.

Storage is deleted before the row, so a failure cannot orphan a screenshot with
nothing left pointing at it.

---

## 5. Draft policy paragraph — for review, not for shipping unread

> During closed testing, this build includes Guidester, an in-app feedback tool.
> When you choose to send feedback, it uploads a screenshot of the screen you are
> looking at, the name you entered, a random identifier generated on your device,
> your device model and OS version, and technical details about the screen
> (app version, text size, light or dark mode, orientation, language, and which
> screen you were on), along with any errors the app ran into while you were
> using it, including the technical details of where they happened. Nothing is
> captured unless you tap send. If you are offline, your feedback is kept on your
> device and sent once you are back online. This data is
> stored in our own database, is not sold or shared with advertisers, and is used
> only to fix the problems you report. You can ask us to delete your feedback at
> any time by contacting &lt;address&gt;, and we will remove it and the screenshots
> with it. Guidester is not present in the public release of this app.

---

## 6. What v0 is not for

**Test builds only.** Screenshots taken in production capture *other people's*
personal data, which makes you a data fiduciary on a live listing and forces a
Data-safety change there.

Production support is a real v1 goal and it needs `GuidesterMask` first — a
widget that redacts its subtree before capture. The hard part of masking is
occlusion, not blur; the incumbent's #380 author hit exactly that and said so.

---

## 7. Gate checklist

- [x] Off by default, and a host that forgets the flag gets nothing
- [x] Consent line in the name prompt, always visible
- [x] Delete a comment, and delete everything from one tester
- [x] Private bucket, signed URLs only, `anon` reaches the API and receives nothing
- [ ] **Play Data safety filled in on the tester build** — yours
- [ ] **Privacy policy paragraph added and reviewed** — yours
- [ ] **The host's existing policy checked for a claim the test build breaks** —
      yours, and the one people skip
- [ ] API key rotated before the closed test if it has been shared anywhere (it is
      extractable from any APK by design)
