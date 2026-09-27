# What gets captured

Everything on this page leaves the device when a tester taps send. Nothing on it leaves at
any other time.

## Only on send

No screenshot is taken, no context gathered and no request made until the tester taps
**Send**. Tapping the bubble arms comment mode; tapping the screen captures a frame *into
memory*; sending is what uploads. Cancel and it is discarded.

The one exception is the launch ping: when the overlay mounts it tells the backend that
this key is alive, carrying the device model, OS version and app version. No screenshot, no
comment. It is what makes the dashboard's connection check honest.

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

## The device

Model, manufacturer, OS version, whether it is a physical device or an emulator, screen
size, pixel ratio, **text scale factor**, **platform brightness**, orientation, locale,
timezone offset, app version, and the last five screens visited.

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

## What is never captured

No location, no contacts, no advertising identifier, no hardware identifier, no keystrokes
outside the comment box, and nothing at all from a build that passes no key.

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
