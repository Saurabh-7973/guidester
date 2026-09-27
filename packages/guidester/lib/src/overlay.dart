import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'api_client.dart';
import 'bubble_position.dart';
import 'capture_context.dart';
import 'capture_warnings.dart';
import 'draft_store.dart';
import 'error_recorder.dart';
import 'guidester.dart';
import 'impact.dart';
import 'outbox.dart';
import 'screen_resolver.dart';
import 'tester_identity.dart';
import 'theme/tokens.dart';
import 'ui/bubble.dart';
import 'ui/composer.dart';
import 'ui/mode_bar.dart';
import 'ui/name_prompt.dart';
import 'ui/retest_list.dart';

/// Wraps the running app. Never pushes a route, never replaces the tree.
///
/// Install via `MaterialApp.builder`, not around `MaterialApp`: that puts
/// `Directionality`, `MediaQuery` and `Material` in scope while sitting above
/// the `Navigator`, so every route is covered and the host's theme is untouched.
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => GuidesterOverlay(child: child!),
///   // Only for Navigator.pushNamed apps; Router apps need nothing here.
///   navigatorObservers: [Guidester.observer],
/// );
/// ```
///
/// `MaterialApp.router` takes the same `builder`. When [Guidester.isEnabled]
/// is false (no key was passed) this returns [child] unchanged, so a release
/// build without the key carries no bubble, no capture and no network call.
class GuidesterOverlay extends StatefulWidget {
  const GuidesterOverlay({super.key, required this.child, this.client});

  /// Your app: the `child` that `MaterialApp.builder` hands you.
  final Widget child;

  /// Where comments are sent. Null, the default, posts to the endpoint given to
  /// [Guidester.init]. Tests and the in-browser demo pass their own.
  final ApiClient? client;

  @override
  State<GuidesterOverlay> createState() => _GuidesterOverlayState();
}

class _GuidesterOverlayState extends State<GuidesterOverlay>
    with WidgetsBindingObserver {
  static const Duration _captureTimeout = Duration(seconds: 3);
  static const Duration _contextTimeout = Duration(seconds: 2);

  /// How long the launch ping will wait for the device-local tester id. Local
  /// storage answers in milliseconds when it answers at all.
  static const Duration _testerIdBudget = Duration(milliseconds: 500);

  final GlobalKey _boundaryKey = GlobalKey();

  late final ApiClient _api = widget.client ?? ApiClient();
  bool _ownsClient = false;
  late final OutboxSender _outbox = OutboxSender(_api, onSent: _onQueuedSent);

  bool _commentMode = false;
  Offset? _pin;
  Size? _boundarySize;
  Uint8List? _shot;
  bool _sending = false;
  String? _error;
  String _draft = '';

  /// Set when [_draft] came back from an earlier launch: the screen it was
  /// written on. Cleared once the draft is sent or discarded.
  String? _restoredFrom;
  Impact _impact = Impact.fallback;
  String _screenName = 'UNKNOWN';

  /// Regions the platform composites and the screenshot cannot show. Found at
  /// pin time, before the composer covers anything.
  List<BlankRegion> _blank = const [];
  int _screenLayer = 0;
  bool _awaitingName = false;

  /// What a developer has marked fixed and this tester has not answered yet.
  /// Arrives on the launch ping's 200 — D60, and there is no other request.
  List<PendingRetest> _retests = const [];
  bool _retestsOpen = false;
  String? _answering;
  String? _retestError;
  String? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    Guidester.debugMarkOverlayMounted();
    WidgetsBinding.instance.addObserver(this);
    _pingOnLaunch();
    _restoreDraft();
    if (Guidester.isEnabled) unawaited(_outbox.kick());
  }

  /// Back in the foreground is the likeliest moment the network came back:
  /// the tester left the lift, or switched Wi-Fi on in settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Guidester.isEnabled) {
      unawaited(_outbox.kick());
    }
  }

  void _onQueuedSent(int sent) {
    if (!mounted) return;
    _showToast(
      sent == 1 ? 'Saved comment sent' : '$sent saved comments sent',
    );
  }

  void _showToast(
    String text, {
    Duration duration = const Duration(seconds: 2),
  }) {
    setState(() => _toast = text);
    _toastTimer?.cancel();
    _toastTimer = Timer(duration, () {
      if (mounted) setState(() => _toast = null);
    });
  }

  /// Android Back while the overlay has something open closes that, not the
  /// host's screen underneath (field test, 25 Sep: the route popped and the
  /// sheet stayed, so the comment filed against a screen already left). With
  /// nothing open, Back is the app's own.
  ///
  /// Two paths, because Flutter asks binding observers in the order they
  /// registered. In a Router app the Router registers after this overlay,
  /// so [didPopRoute] here runs first. In a Navigator 1.0 app WidgetsApp
  /// registered before it and pops first, so the overlay also hangs a local
  /// history entry on the top route while something is open: the Navigator
  /// removes the entry instead of the route, which is how drawers and
  /// persistent sheets do it.
  @override
  Future<bool> didPopRoute() async {
    if (!_somethingOpen) return false;
    _closeFromBack();
    return true;
  }

  bool get _somethingOpen => _commentMode || _pin != null || _retestsOpen;

  LocalHistoryEntry? _backEntry;

  void _syncBackEntry() {
    final open = _somethingOpen;
    if (open && _backEntry == null) {
      final route = Guidester.observer.topRoute;
      if (route is ModalRoute && route.isActive) {
        final entry = LocalHistoryEntry(
          onRemove: _onBackEntryRemoved,
          // Without this the host's AppBar reads the entry as "there is
          // somewhere to go back to" and shows a back arrow on a root screen
          // for as long as the sheet is up (demo recording, 27 Sep).
          impliesAppBarDismissal: false,
        );
        _backEntry = entry;
        route.addLocalHistoryEntry(entry);
      }
    } else if (!open && _backEntry != null) {
      final entry = _backEntry!;
      _backEntry = null; // before remove(): this is not a Back press
      entry.remove();
    }
  }

  void _onBackEntryRemoved() {
    if (_backEntry == null) return; // removed by _syncBackEntry
    _backEntry = null;
    if (mounted) _closeFromBack();
  }

  /// The draft stays saved: Back is "not now", not "throw it away".
  void _closeFromBack() {
    if (_retestsOpen && _pin == null) {
      setState(() {
        _retestsOpen = false;
        _retestError = null;
      });
      return;
    }
    _reset(keepCommentMode: false, discardDraft: false);
  }

  /// Field test S15: a tester force-stopped mid-sentence lost the sentence.
  Future<void> _restoreDraft() async {
    if (!Guidester.isEnabled) return;
    final draft = await DraftStore.load();
    // A comment already started in this launch wins over one from the last.
    if (draft == null || !mounted || _draft.isNotEmpty || _pin != null) return;
    setState(() {
      _draft = draft.text;
      _impact = draft.impact;
      _restoredFrom = draft.screenName;
    });
  }

  void _onDraftChanged(String text, Impact impact) {
    // No setState: the composer owns what is on screen. This is only so the
    // name prompt and the next launch can hand the same words back.
    _draft = text;
    _impact = impact;
    unawaited(
      DraftStore.save(
        text: text,
        impact: impact,
        screenName: _restoredFrom ?? _screenName,
      ),
    );
  }

  /// DEVIATION from product spec §3.2, which puts the launch ping in
  /// `Guidester.init`. It fires here instead, when the overlay mounts.
  ///
  /// Two reasons. The install is two changes, not one — the `init` call and
  /// this widget — and a host that made only the first has an app that cannot
  /// produce a single comment. A ping from `init` would tell the onboarding
  /// screen "connected" about that app, which is the exact false pass the
  /// live check exists to remove. And `init` is documented as touching
  /// nothing: it is called before `runApp`, on the startup path, where the
  /// SDK has no business opening a socket.
  ///
  /// Unawaited and silent by design. Nothing in the app waits for it, no UI
  /// reports it, and a failure is not shown to a tester who did not ask for
  /// anything.
  void _pingOnLaunch() {
    if (!Guidester.isEnabled || !Guidester.debugLaunchPingEnabled) return;
    unawaited(() async {
      // Started alongside the device lookup, not after it, and on a budget of
      // its own. The id is a local shared_preferences read; a store that
      // throws or never answers must cost the return leg only. Announcing the
      // launch is the older job, onboarding depends on it, and it must not
      // start later than it did before this field existed.
      final idFuture = TesterIdentity.id()
          .timeout(_testerIdBudget)
          .then<String?>((v) => v, onError: (_, __) => null);
      try {
        final facts =
            await CaptureContext.collectDevice().timeout(_contextTimeout);
        final testerId = await idFuture;
        final result = await _api.ping(
          deviceModel: facts.deviceModel,
          osVersion: facts.osVersion,
          appVersion: facts.appVersion,
          // The return leg. Without an id the backend answers with an empty
          // list, so this is the whole difference between a ping that can
          // carry something back and one that cannot.
          testerId: testerId,
        );
        if (!mounted || result.retests.isEmpty) return;
        setState(() => _retests = result.retests);
      } catch (_) {
        // A launch that could not be announced is still a launch.
      }
    }());
  }

  @override
  void dispose() {
    // Own every resource we start. No timer, controller or client outlives
    // this widget — leaked overlay state is `feedback`'s #386.
    WidgetsBinding.instance.removeObserver(this);
    final entry = _backEntry;
    _backEntry = null;
    entry?.remove();
    _toastTimer?.cancel();
    _outbox.dispose();
    if (_ownsClient) _api.dispose();
    super.dispose();
  }

  /// Capture the app, and only the app.
  ///
  /// The overlay chrome lives outside this boundary, so it is never in frame.
  Future<Uint8List?> _capture() async {
    final ctx = _boundaryKey.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final w = boundary.size.width;
    if (w <= 0) return null;
    try {
      // A boundary that has not painted this frame throws or returns stale
      // pixels — see flutter/flutter#22308. One frame is enough. Schedule it
      // explicitly: awaiting endOfFrame with no frame pending never completes
      // and would wedge the tap handler.
      if (boundary.debugNeedsPaint) {
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
      }
      final ratio = (720.0 / w).clamp(0.5, 2.0);
      // Bounded: a capture that never completes must not wedge the composer.
      // The comment still sends, just without a screenshot.
      return await () async {
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data?.buffer.asUint8List();
      }()
          .timeout(_captureTimeout, onTimeout: () => null);
    } catch (_) {
      // A failed screenshot must never lose the comment.
      return null;
    }
  }

  Future<void> _onTapDown(TapDownDetails d) async {
    final ctx = _boundaryKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(d.globalPosition);

    // Resolve the screen before anything async can move the app on.
    final resolution = ScreenResolver.resolveDetailed(
      ctx,
      searchRoot: ctx is Element ? ctx : null,
      observer: Guidester.observer,
    );

    final shot = await _capture(); // capture BEFORE the composer draws
    if (!mounted) return;
    // Before the composer draws: the tester is still looking at the screen
    // they are describing, and this is the moment the warning is useful.
    final blank = findBlankRegions(box);

    // The walk, made observable. One line per pin, naming the tag AND the layer
    // that produced it, so a screen-by-screen pass on real hardware can be read
    // off `adb logcat` instead of reconstructed from the dashboard afterwards.
    //
    // Layer is the part that matters. A tag alone cannot tell you whether the
    // router answered or the widget heuristic guessed, and on a Navigator 1.0
    // host every answer comes from the heuristic — which reads class names and
    // can therefore name the wrong one.
    if (Guidester.debugPrintResolvedScreen) {
      debugPrint(
        '[guidester] screen: ${resolution.name} (layer ${resolution.layer})',
      );
    }

    // Diagnostic 5 of 6, before setState so it is not repeated on rebuild. A
    // blank rectangle where a map or a webview was is the most confusing
    // capture result there is: the tester swears they photographed something
    // and the developer sees a hole.
    final blankNote = blankDiagnostic(blank);
    if (blankNote != null) debugPrint(blankNote);

    setState(() {
      _pin = local;
      _boundarySize = box.size;
      _shot = shot;
      _blank = blank;
      _screenName = resolution.name;
      _screenLayer = resolution.layer;
      _error = null;
    });
  }

  /// Back to no pin. [discardDraft] is false for leaving comment mode before
  /// a pin, and for Back with the composer open: in neither has the tester
  /// thrown away what they wrote.
  void _reset({bool keepCommentMode = true, bool discardDraft = true}) {
    if (discardDraft) unawaited(DraftStore.clear());
    final hadComposer = _pin != null;
    setState(() {
      _pin = null;
      _shot = null;
      _boundarySize = null;
      if (discardDraft) {
        _draft = '';
        _impact = Impact.fallback;
        _restoredFrom = null;
      } else if (hadComposer && _draft.trim().isNotEmpty) {
        // Closed with words in it (Back). The next pin may be on another
        // screen, and the tester is told where these were written, as a
        // relaunch already tells them. Found recording the demo, 27 Sep.
        _restoredFrom ??= _screenName;
      }
      _blank = const [];
      _error = null;
      _sending = false;
      _awaitingName = false;
      _commentMode = keepCommentMode;
    });
  }

  Future<void> _send(String text, Impact impact) async {
    if (_sending) return; // guard: double-tap must not ship two comments
    // Held on the state, not just passed down: the name prompt replaces the
    // composer, so an un-held chip selection would be lost on the way back.
    _draft = text;
    _impact = impact;

    final name = await TesterIdentity.name();
    if (!mounted) return;
    if (name == null) {
      setState(() => _awaitingName = true);
      return;
    }
    await _dispatch(text, name);
  }

  Future<void> _dispatch(String text, String testerName) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final size = _boundarySize;
      final pin = _pin;
      final ctx = _boundaryKey.currentContext;
      // Bounded: context is valuable but never worth losing a comment over.
      // A platform channel that never answers must not hold the send open.
      CaptureContext? captured;
      if (ctx != null) {
        try {
          captured = await CaptureContext.collect(
            ctx,
            routeStack: Guidester.observer.breadcrumb,
            screenResolverLayer: _screenLayer,
          ).timeout(_contextTimeout);
        } on TimeoutException {
          captured = null;
        }
      }
      final testerId = await TesterIdentity.id();

      final payload = ApiClient.commentPayload(
        body: text,
        screenName: _screenName,
        tapX: (pin != null && size != null && size.width > 0)
            ? pin.dx / size.width
            : null,
        tapY: (pin != null && size != null && size.height > 0)
            ? pin.dy / size.height
            : null,
        screenshot: _shot,
        testerName: testerName,
        testerId: testerId,
        impact: _impact,
        blankRegions: _blank,
        errors: ErrorRecorder.toJson(),
        context: captured,
        clientId: Outbox.newClientId(),
      );
      final result = await _api.sendPayload(payload);
      if (!mounted) return;
      if (result.success) {
        // Back to IDLE, not comment mode. Reverses build guide §5.6.
        //
        // While armed, the tap catcher covers the whole app and swallows every
        // navigation tap, so a tester who has just sent a comment cannot reach
        // the next screen — they tap a tab, place a pin instead, and never
        // move. That is why D44's three tab comments all resolved to TODAY and
        // why the field test's eight comments are all tagged ONBOARDING: the
        // resolver was right every time, the app genuinely never navigated.
        //
        // Two comments on one screen now costs one extra tap on the bubble.
        // The fourteen-day test measures coverage across screens; being unable
        // to navigate costs the test.
        _reset(keepCommentMode: false);
        _showToast('Comment sent');
        // It went, so the network is back: anything queued goes now too.
        unawaited(_outbox.kick());
      } else if (result.retryable && await Outbox.add(payload)) {
        // No network, or the server had a bad minute. The comment is on
        // disk with its screenshot, so the composer closes as if it went,
        // and the tester is told the one thing that differs.
        if (!mounted) return;
        _reset(keepCommentMode: false);
        _showToast(
          'No connection. Saved — it will send when you\'re back online.',
          duration: const Duration(seconds: 4),
        );
        _outbox.later();
      } else {
        if (!mounted) return;
        setState(() => _error = result.error); // text is preserved
      }
    } finally {
      // Cleared in a finally so a thrown error cannot wedge the button.
      if (mounted) setState(() => _sending = false);
    }
  }

  /// A tester answering the ask: "Works now" or "Still broken".
  ///
  /// Both write `tester_verdict` through the ingest function that already
  /// handles writes — no new endpoint, and the backend checks twice over that
  /// the row is in this key's project AND carries this tester_id.
  ///
  /// "Still broken" then arms comment mode with the report's own words in the
  /// draft. That is the reason this lives in the app instead of behind a link:
  /// the answer "no" can carry a fresh screenshot of the build in the tester's
  /// hand, which is the product's whole claim applied to the second half of
  /// the loop.
  Future<void> _answerRetest(
    PendingRetest item, {
    required bool accepted,
  }) async {
    if (_answering != null) return; // one answer in flight at a time
    setState(() {
      _answering = item.id;
      _retestError = null;
    });

    final testerId = await TesterIdentity.id();
    final result = await _api.sendVerdict(
      commentId: item.id,
      testerId: testerId,
      accepted: accepted,
    );
    if (!mounted) return;

    if (!result.success) {
      // An unanswered report stays on the list. Dropping it here would tell
      // the tester they had replied when the server never heard it.
      setState(() {
        _answering = null;
        _retestError = result.error;
      });
      return;
    }

    final remaining = [
      for (final r in _retests)
        if (r.id != item.id) r,
    ];
    setState(() {
      _answering = null;
      _retests = remaining;
      _retestsOpen = false;
      _retestError = null;
      if (!accepted) {
        _commentMode = true;
        _draft = 'Still broken: ${item.excerpt}';
      }
    });
    if (accepted) _flash('Thanks — marked as fixed');
  }

  void _flash(String message) {
    setState(() => _toast = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // After this frame, so the entry follows what is actually on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncBackEntry();
    });
    // The production kill switch. Must be the first line: with this returning
    // early, no capture, no network call and no overlay is reachable.
    if (!Guidester.isEnabled) return widget.child;

    final media = MediaQuery.of(context);
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),

        // Our chrome gets its own Overlay. It has to: the chrome sits above
        // the host's Navigator (so it stays out of the screenshot), and a
        // TextField with no Overlay ancestor asserts as soon as it takes
        // focus. This is a local Overlay owned by this widget — the host's
        // navigator is never touched, and Flutter disposes the entry with the
        // element, so there is nothing to leak.
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(builder: (context) => _chrome(context, media)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chrome(BuildContext context, MediaQueryData media) {
    // D42: every Material widget below resolves its defaults from the nearest
    // Theme, and the nearest Theme is the host's — so the chrome renders in
    // Sahaj's amber without a single `Theme.of` call anywhere in this package.
    // The CI grep for `Theme.of` passes and always did; it tests the wrong
    // thing.
    //
    // The fix is a boundary, not a move. `GuidesterOverlay` stays inside
    // `MaterialApp.builder` because that placement is what puts Directionality,
    // MediaQuery and text selection in scope while sitting above the host's
    // Navigator. Wrapping the chrome — and only the chrome — in our own Theme
    // keeps the position and cuts the inheritance. `widget.child` is outside
    // this subtree, so the host keeps its own theme untouched.
    return Theme(
      data: GT.theme,
      child: _chromeStack(context, media),
    );
  }

  Widget _chromeStack(BuildContext context, MediaQueryData media) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        // Tap catcher exists ONLY while armed and unplaced. Leaving it up
        // would swallow taps meant for the composer.
        if (_commentMode && _pin == null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _onTapDown,
              child: const SizedBox.expand(),
            ),
          ),

        // While the composer is open the app underneath must not take taps.
        // Found recording the demo, 27 Sep: a tap above the sheet navigated
        // the app to another screen while the composer kept the old screen's
        // name and screenshot, so the comment filed against a screen the
        // tester had already left. The same failure the Back handling closes,
        // through a different door. A tap here only puts the keyboard away.
        if (_pin != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: const SizedBox.expand(),
            ),
          ),

        if (_pin != null)
          Positioned(
            left: _pin!.dx - 11,
            top: _pin!.dy - 11,
            child: const GuidesterPin(),
          ),

        if (_commentMode && _pin == null)
          Positioned(
            top: media.padding.top + 12,
            left: 16,
            right: 16,
            child: Center(
              child: GuidesterModeBar(
                onCancel: () =>
                    _reset(keepCommentMode: false, discardDraft: false),
              ),
            ),
          ),

        if (!_commentMode && _pin == null)
          _DraggableBubble(
            media: media,
            onTap: () => setState(() => _commentMode = true),
            badgeCount: _retests.length,
            onBadgeTap: () => setState(() => _retestsOpen = true),
          ),

        // The list sits where the composer sits, and never at the same time:
        // answering is a different job from reporting.
        if (_retestsOpen && _pin == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Sheet(
              child: GuidesterRetestList(
                items: _retests,
                busyId: _answering,
                error: _retestError,
                onAnswer: (item, {required bool accepted}) =>
                    unawaited(_answerRetest(item, accepted: accepted)),
                onClose: () => setState(() {
                  _retestsOpen = false;
                  _retestError = null;
                }),
              ),
            ),
          ),

        if (_pin != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Sheet(
              child: _awaitingName
                  ? GuidesterNamePrompt(
                      onSubmit: (name) async {
                        await TesterIdentity.setName(name);
                        if (!mounted) return;
                        setState(() => _awaitingName = false);
                        await _dispatch(_draft, name);
                      },
                    )
                  : GuidesterComposer(
                      screenName: _screenName,
                      sending: _sending,
                      error: _error,
                      initialText: _draft,
                      initialImpact: _impact,
                      blankWarning: blankWarning(_blank),
                      restoredFrom: _restoredFrom,
                      onChanged: _onDraftChanged,
                      onSend: _send,
                      onCancel: _reset,
                    ),
            ),
          ),

        if (_toast != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: media.padding.bottom + 90,
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: Material(
                  // Not --green: that is the completed-step token in
                  // onboarding, and a green toast collides with it. The frames
                  // show "Comment Sent" as a dark pill.
                  color: GT.surface4,
                  shape: const StadiumBorder(
                    side: BorderSide(color: GT.chromeBorder),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      _toast!,
                      style: const TextStyle(color: GT.text1, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // --surface-4, the lightest step, with an explicit border and shadow.
    // Floating chrome cannot borrow separation from a background it does not
    // know: #131313 over a warm dark host dissolves into it.
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: GT.chromeBorder)),
        boxShadow: [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, spreadRadius: 2),
        ],
      ),
      child: Material(
        color: GT.surface4,
        elevation: 0,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GT.rPanel),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The bubble, movable and remembered.
///
/// B6 fixed it bottom-right. D44 found it sitting on Sahaj's "Me" tab, and any
/// host with bottom navigation lands in the same place — so it drags, snaps to
/// the nearer vertical edge on release, and comes back where the tester left
/// it. Horizontal freedom is deliberately not offered: an arbitrary position
/// mid-screen covers content without the tester meaning it, and an edge is
/// where a floating control belongs.
class _DraggableBubble extends StatefulWidget {
  const _DraggableBubble({
    required this.media,
    required this.onTap,
    this.badgeCount = 0,
    this.onBadgeTap,
  });

  final MediaQueryData media;
  final VoidCallback onTap;

  /// How many reports are waiting on this tester. Zero draws nothing.
  final int badgeCount;
  final VoidCallback? onBadgeTap;

  @override
  State<_DraggableBubble> createState() => _DraggableBubbleState();
}

class _DraggableBubbleState extends State<_DraggableBubble> {
  static const double _size = 52;
  static const double _margin = 16;

  bool _right = BubblePosition.defaultOnRight;
  double _yFraction = BubblePosition.defaultYFraction;

  /// Live pixel position while a drag is in flight; null when resting.
  Offset? _dragging;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final right = await BubblePosition.onRight();
    final y = await BubblePosition.yFraction();
    if (!mounted) return;
    setState(() {
      _right = right;
      _yFraction = y;
      _loaded = true;
    });
  }

  /// The vertical band the bubble may occupy, inset by the safe areas so it
  /// never sits under a notch or a gesture bar.
  ({double top, double bottom}) _band(Size screen) {
    final top = widget.media.padding.top + _margin;
    final bottom =
        screen.height - widget.media.padding.bottom - _margin - _size;
    // A very short screen (or a large font scale on a small phone) can invert
    // these. Collapse to a single valid position rather than produce a
    // negative range.
    return bottom < top ? (top: top, bottom: top) : (top: top, bottom: bottom);
  }

  @override
  Widget build(BuildContext context) {
    // Positioned must be a direct child of a Stack, so the LayoutBuilder that
    // measures the screen gets its own: this fills the chrome stack, then
    // positions the bubble inside itself. The filling stack is empty apart
    // from the bubble, so it intercepts nothing.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screen = Size(constraints.maxWidth, constraints.maxHeight);
          final band = _band(screen);
          final travel = band.bottom - band.top;

          final resting = Offset(
            _right ? screen.width - _margin - _size : _margin,
            band.top + travel * _yFraction,
          );
          final at = _dragging ?? resting;

          return Stack(
            children: [
              Positioned(
                left: at.dx,
                top: at.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => setState(() => _dragging = resting),
                  onPanUpdate: (d) {
                    final from = _dragging ?? resting;
                    setState(() {
                      _dragging = Offset(
                        (from.dx + d.delta.dx).clamp(0.0, screen.width - _size),
                        (from.dy + d.delta.dy).clamp(band.top, band.bottom),
                      );
                    });
                  },
                  onPanEnd: (_) {
                    final released = _dragging;
                    if (released == null) return;
                    final right =
                        BubblePosition.snapsRight(released.dx, screen.width);
                    final fraction = travel <= 0
                        ? 0.0
                        : ((released.dy - band.top) / travel).clamp(0.0, 1.0);
                    setState(() {
                      _right = right;
                      _yFraction = fraction;
                      _dragging = null; // snap: the resting position takes over
                    });
                    // Fire and forget — a failed write costs the position on the
                    // next launch, never the drag the tester just made.
                    BubblePosition.save(right: right, y: fraction);
                  },
                  child: Opacity(
                    // Until prefs answer, the bubble is at the default
                    // position; a one-frame jump to a remembered edge reads
                    // as a glitch.
                    opacity: _loaded ? 1.0 : 0.0,
                    child: GuidesterBubble(onTap: widget.onTap),
                  ),
                ),
              ),

              // Its own hit target, deliberately. Tapping the bubble arms
              // comment mode and always has; a badge that hijacked that tap
              // would make the main action depend on what the server said.
              if (widget.badgeCount > 0 && widget.onBadgeTap != null)
                Positioned(
                  left: at.dx + _size - 18,
                  top: at.dy - 4,
                  child: Opacity(
                    opacity: _loaded ? 1.0 : 0.0,
                    child: GuidesterRetestBadge(
                      key: const Key('guidester.retest.badge'),
                      count: widget.badgeCount,
                      onTap: widget.onBadgeTap!,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
