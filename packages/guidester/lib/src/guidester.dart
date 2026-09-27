import 'package:flutter/widgets.dart';

import 'error_recorder.dart';
import 'outbox.dart';
import 'screen_resolver.dart';

/// Static entry point and configuration holder.
///
/// Nothing here allocates or touches the network. [init] only records
/// configuration; capture happens in `GuidesterOverlay`.
class Guidester {
  Guidester._();

  static String? _apiKey;
  static String? _endpoint;
  static bool _enabled = false;

  /// Attach to `MaterialApp.navigatorObservers` to enable layer 2 of the
  /// screen resolver. Optional — layers 3 and 4 work without it.
  static final GuidesterRouteObserver observer = GuidesterRouteObserver();

  /// Whether this build passed `--dart-define=GUIDESTER=true`.
  ///
  /// **No longer the switch.** Since 0.3.0 the api key is: an empty key means
  /// nothing runs. This is kept because builds and scripts in the wild still
  /// pass the define, and reading it as false when it was set to true would be
  /// a silent surprise.
  ///
  /// To turn the SDK off despite a key being present, pass
  /// `--dart-define=GUIDESTER=false`, which is read as a string precisely
  /// because a bool cannot tell "not passed" from "passed as false".
  static const bool compiledIn = bool.fromEnvironment(
    'GUIDESTER',
    defaultValue: false,
  );

  /// Which backend this build points at: `uat`, `live`, `staging` — whatever
  /// the team calls them.
  ///
  /// Only the WhatsApp thread revealed how much this costs to leave out. The
  /// bug sheet has no environment column, and the group is full of the gap:
  /// *"Issue in Live envoirnment"*, *"working in uat not in live"*,
  /// *"please specify Env"*, *"25 Jun - check in prod"*. A bug that reproduces
  /// in UAT and not in Live is a different bug, and today the answer lives in
  /// prose or in a developer's follow-up question.
  ///
  /// The build already knows. `--dart-define=GUIDESTER_ENV=uat`.
  static const String environment = String.fromEnvironment(
    'GUIDESTER_ENV',
    defaultValue: '',
  );

  /// An explicit off switch that survives a key being present.
  ///
  /// `bool.fromEnvironment` cannot tell "not passed" from "passed as false",
  /// which is exactly the distinction needed once the key alone arms the SDK.
  /// Read as a string instead: unset means "decide from the key", and the
  /// literal `false` means off no matter what else is true.
  ///
  /// `--dart-define=GUIDESTER=false`
  static const String _switch = String.fromEnvironment('GUIDESTER');

  /// Configure the SDK. Call once, before `runApp`.
  ///
  /// The whole install:
  ///
  /// ```dart
  /// Guidester.init(
  ///   apiKey: const String.fromEnvironment('GUIDESTER_KEY'),
  ///   endpoint: const String.fromEnvironment('GUIDESTER_ENDPOINT'),
  /// );
  /// ```
  ///
  /// **The key is the kill switch.** A production build passes no
  /// `--dart-define=GUIDESTER_KEY`, so the key is empty, so `isEnabled` is
  /// false, so `GuidesterOverlay.build` returns its child on its first line and
  /// no capture or network path is reachable. A host that forgets the define
  /// gets an SDK that does nothing, which is the right way round: this uploads
  /// screenshots and device identifiers off-device, and the failure mode of a
  /// default-on switch is doing that to people who never agreed to it.
  ///
  /// [endpoint] is your deployment of the `ingest` edge function. There is no
  /// default: this package ships no backend URL (D71). Pass it the same way as
  /// the key, `--dart-define=GUIDESTER_ENDPOINT=<url>`, and an empty value
  /// disables the SDK and says so.
  ///
  /// [enabled] is an override for anyone who hardcodes a key and needs a
  /// separate switch. Leave it null and the key decides. Passing it explicitly
  /// still works, and `--dart-define=GUIDESTER=false` turns everything off
  /// regardless.
  static void init({
    required String apiKey,
    required String endpoint,
    bool? enabled,
  }) {
    _apiKey = apiKey;
    _endpoint = endpoint;
    _enabled = (enabled ?? _switch != 'false') &&
        apiKey.isNotEmpty &&
        endpoint.isNotEmpty;

    // Diagnostic 1 of 6. Silence is the worst possible answer to a
    // misconfiguration: without this the symptom is "no bubble", which is
    // indistinguishable from a broken install, a wrong key, and a missing
    // overlay.
    if (!_enabled && apiKey.isEmpty) {
      debugPrint(
        '[guidester] disabled — GUIDESTER_KEY is empty. Pass '
        '--dart-define=GUIDESTER_KEY=<your key> to a test build. Production '
        'builds are meant to look like this.',
      );
    } else if ((enabled ?? _switch != 'false') && endpoint.isEmpty) {
      debugPrint(
        '[guidester] disabled — GUIDESTER_ENDPOINT is empty. Pass '
        '--dart-define=GUIDESTER_ENDPOINT=<your ingest URL>. There is no '
        'default backend; see doc/self-hosting.md.',
      );
    }
    _initCalled = true;
    // Diagnostic 6 of 6, here rather than at the first failed resolve: a
    // developer who never files a comment never resolves a screen, and
    // --obfuscate removes every layer 4 tag at once. Only for a build that is
    // actually running the SDK — a production build narrates nothing.
    if (_enabled) ScreenResolver.warnIfObfuscated();
    _warnIfOverlayNeverMounts();
    // Errors start being recorded here rather than when the overlay mounts:
    // the ones thrown while the first screen builds are the ones a tester
    // reports as "it opened to a white screen", and by the time an overlay
    // exists they have already happened.
    //
    // Installs nothing when disabled — a production build chains no handlers.
    ErrorRecorder.install();
  }

  /// Whether the SDK is on: [init] was called with a non-empty key and
  /// endpoint, and neither `enabled: false` nor `--dart-define=GUIDESTER=false`
  /// turned it off. When false, [GuidesterOverlay] returns its child untouched.
  static bool get isEnabled => _enabled;

  static bool _initCalled = false;
  static bool _overlayMounted = false;

  /// Called by `GuidesterOverlay` when it mounts. Turns off diagnostic 2.
  static void debugMarkOverlayMounted() => _overlayMounted = true;

  /// Whether the mount watchdog runs. Off across this package's own suite:
  /// a pending timer when a widget test ends fails that test, and most tests
  /// here never mount an overlay on purpose.
  static bool debugMountWarningEnabled = true;

  /// Whether each placed pin prints the screen it resolved to and the layer
  /// that produced it.
  ///
  /// On for the same reason the other diagnostics are: a developer walking
  /// their app to check the tags cannot otherwise see which layer answered,
  /// and layer 4 answering is the case worth catching. One line per comment,
  /// not per frame.
  static bool debugPrintResolvedScreen = true;

  /// Diagnostic 2 of 6, and the one that costs the most support time.
  ///
  /// `init()` with no `GuidesterOverlay` in the tree is a silent, complete
  /// failure: configuration is correct, the key is valid, the backend is
  /// reachable, and not one comment can ever be filed. The symptom is "no
  /// bubble", which looks exactly like four other problems.
  ///
  /// Deliberately a delay rather than a post-frame callback: the overlay is
  /// built by `MaterialApp`'s `builder`, which does not necessarily run in the
  /// first frame after `runApp`.
  static void _warnIfOverlayNeverMounts() {
    if (!_enabled || !debugMountWarningEnabled) return;
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (_initCalled && !_overlayMounted) {
        debugPrint(
          '[guidester] init() was called but GuidesterOverlay was never '
          'mounted, so no comment can be filed. Add '
          'builder: (context, child) => GuidesterOverlay(child: child!) '
          'to your MaterialApp.',
        );
      }
    });
  }

  /// Whether a mounted `GuidesterOverlay` announces the launch to the backend.
  ///
  /// True in every real build. False across this package's own test suite —
  /// see `test/flutter_test_config.dart` — because the ping is a network call
  /// on a timer, and a timer still pending when a widget test ends fails that
  /// test wherever it was started from. The ping's own tests turn it back on
  /// deliberately, which is also the only way to be sure they are testing it.
  /// Not marked `@visibleForTesting`: the overlay itself reads it, and an
  /// annotation the library has to violate teaches nothing.
  static bool debugLaunchPingEnabled = true;

  /// The project key passed to [init], or empty.
  static String get apiKey => _apiKey ?? '';

  /// The ingest endpoint passed to [init], or empty.
  static String get endpoint => _endpoint ?? '';

  /// Override the screen name for everything captured from here on.
  /// Layer 1 of the resolver — always wins. Clear it with null.
  static void setScreen(String? name) => ScreenResolver.manual = name;

  /// Which resolver layer would produce the current screen name, and what it
  /// would be. Useful when a dashboard fills up with `UNKNOWN`.
  static ScreenResolution debugResolveScreen(BuildContext context) =>
      ScreenResolver.resolveDetailed(context, observer: observer);

  /// Test seam. Resets all configuration to defaults.
  @visibleForTesting
  static void debugReset() {
    _apiKey = null;
    _endpoint = null;
    _enabled = false;
    _initCalled = false;
    _overlayMounted = false;
    ErrorRecorder.debugReset();
    Outbox.debugReset();
    ScreenResolver.manual = null;
    observer.debugReset();
  }
}
