# What gets captured

Everything on this page is what the SDK sends or keeps. Most of it leaves the device when a
tester taps **Send**; the exceptions are listed under each heading, and nothing leaves from a
build that passes no key.

## Only on send

No screenshot is taken, no context gathered and no request made until the tester taps
**Send**. Tapping the bubble arms comment mode; tapping the screen captures a frame *into
memory*; sending is what uploads. Cancel and it is discarded.

Two exceptions:

- **The launch ping.** When the overlay mounts it tells the backend that this key is alive,
  carrying the device model, OS version, app version and the tester id (so the answer can
  list the fixes waiting for this tester to check). No screenshot, no comment. It is what
  makes the dashboard's connection check honest.
- **A comment sent without a connection** is kept on the device and sent later, on its own:
  on the next launch, when the app returns to the foreground, or after another comment goes
  through. See *Kept on the device* below.

## The comment

| Field | Where it comes from |
|---|---|
| The text | typed by the tester |
| Impact | blocked, annoying or cosmetic, chosen by the tester |
| Screen name | resolved automatically, plus which layer resolved it |
| Tap position | normalised 0..1, so the dashboard can pin it at any scale |
| Screenshot | one PNG of the screen, **excluding** the overlay's own chrome |
| Tester name | typed once, stored on the device, not an account |
| Tester id | a random value generated on the device |
| Comment id | a random value made per comment, so a retried send is stored once |
| Environment | the `GUIDESTER_ENV` define, when the build sets one (`uat`, `staging`) |
| Blank regions | where the screenshot is blank because a platform view (map, web view, camera) could not be captured, and which kind |

## The device

Model, manufacturer, OS version, whether it is a physical device or an emulator, screen
size, pixel ratio, **text scale factor**, **platform brightness**, orientation, locale,
timezone offset, app version, build number, package name, the Guidester SDK version, and
the last five screens visited.

Those middle three close a surprising number of reports on their own. "It looks broken" is
usually a large font scale, dark mode, or an emulator.

## The errors

When enabled, the SDK chains `FlutterError.onError` and
`PlatformDispatcher.instance.onError`, keeps the **last three errors of the session**, and
sends them with the next comment: the exception text, up to 24 stack frames, the Flutter
library that reported it, and the route it happened on.

Nothing is swallowed. Both handlers call whatever was installed before them, so a crash
still crashes and your crash reporter still sees what it saw.

**Read this twice before shipping a test build.** An exception message can quote your app's
own data. `Invalid argument: user@example.com` is an ordinary Dart error, and the SDK cannot
tell that string from any other. Nothing redacts it.

## Answers to "please check this fix"

When a developer marks a report fixed, the tester's next launch shows it. Answering *Works
now* or *Still broken* sends the report's id, the tester id and the answer. *Still broken*
then opens the composer, and what the tester sends is an ordinary comment.

## Kept on the device

- The tester's name and the random tester id, until the app's data is cleared.
- An unsent draft, until it is sent or discarded.
- **Comments that could not be sent**, each with its screenshot, as files in the app's own
  storage: at most 20, for at most 14 days, deleted once sent. Not on the web.

## What is never captured

No location, no contacts, no advertising identifier, no hardware identifier, no keystrokes
outside the comment box, and nothing at all from a build that passes no key.

## Posted to a team channel, if you connect one

Nothing, unless an owner or admin connects a Slack, Discord or Microsoft Teams channel in
the dashboard (Settings → Notifications). Then each new comment's text, screen name,
impact, tester name, device model, OS version and build are posted to that channel as
it arrives. The screenshot, the tester id, the error stacks and the device context are
not.

## Test builds only

Screenshots from a production build capture *other people's* personal data, which makes you
a data controller on a live listing. Redaction — a widget that blanks its subtree before
capture — does not exist yet. Until it does, this belongs in builds that go to people who
know they are testing.

## What you must declare

If you ship a test build through Play or TestFlight, declare photos/videos, device
identifiers and app activity as collected and transferred off-device, purpose *app
functionality*.

And read your own privacy policy before you add a paragraph to it. The line to look for is
any promise that data stays on the device — a test build makes it untrue for that cohort,
and no appended paragraph fixes a contradiction earlier on the same page.
