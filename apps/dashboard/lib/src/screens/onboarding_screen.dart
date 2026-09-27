import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/project_repository.dart';
import '../theme/tokens.dart';
import '../widgets/controls.dart';
import '../widgets/guides.dart';
import '../widgets/onboarding_previews.dart';

/// Spec §2 — `Home__1_` through `Home__4_`.
///
/// Split canvas: the left panel is the flow, the right panel is a preview that
/// bleeds off the right edge on purpose. Three steps, and the third one does
/// not ask whether the install worked — it watches for the SDK's first launch
/// ping and says so. Self-reported success is the weakest check in the flow
/// (product spec §3.2), and people click Yes to get past it.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.repository,
    required this.endpoint,
    required this.onFinished,
    required this.onCancel,
    this.pollInterval = const Duration(seconds: 3),
  });

  final ProjectRepository repository;

  /// The ingest URL this dashboard's own backend serves, pasted into the
  /// snippet the developer copies. Nobody should be typing this by hand.
  final String endpoint;

  /// Called with the finished project so the caller can open it.
  final ValueChanged<Project> onFinished;
  final VoidCallback onCancel;

  /// How often step 03 asks whether the key has been used. Injectable so a
  /// test does not wait three seconds to find out.
  final Duration pollInterval;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _name = TextEditingController();

  int _step = 0;
  bool _creating = false;
  String? _error;

  Project? _project;
  ProjectKey? _key;

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final (project, key) = await widget.repository.create(_name.text.trim());
      if (!mounted) return;
      setState(() {
        _project = project;
        _key = key;
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _toStep3() {
    setState(() => _step = 2);
    _startPolling();
  }

  /// Ask the database, on a timer, whether anything has reported on this key.
  ///
  /// A poll rather than a realtime subscription: this runs for the two minutes
  /// somebody spends installing an SDK, and a websocket plus its RLS
  /// configuration is a lot of machinery for a question asked forty times.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(widget.pollInterval, (_) => _refreshKey());
    unawaited(_refreshKey());
  }

  Future<void> _refreshKey() async {
    final project = _project;
    if (project == null) return;
    try {
      final keys = await widget.repository.keys(project.id);
      if (!mounted || keys.isEmpty) return;
      setState(() => _key = keys.first);
      if (keys.first.hasBeenUsed) _poll?.cancel();
    } catch (_) {
      // A failed poll is not an error the developer can act on, and the next
      // one is three seconds away.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Right panel from x=860, bleeding off the right edge — clipped on
        // purpose, per §2. It is drawn first so the left panel stays on top of
        // anything that reaches back under it.
        Positioned(
          left: 860,
          top: 0,
          bottom: 0,
          right: -400,
          child: switch (_step) {
            0 => ProjectPreview(name: _name.text.trim()),
            1 => const InstallPreview(),
            _ => const PhonePreview(),
          },
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 783,
          child: _LeftPanel(
            step: _step,
            child: switch (_step) {
              0 => _StepName(
                controller: _name,
                busy: _creating,
                error: _error,
                onSubmit: _create,
              ),
              1 => _StepInstall(onDone: _toStep3),
              _ => _StepWire(
                endpoint: widget.endpoint,
                apiKey: _key?.key ?? '',
                connected: _key?.hasBeenUsed ?? false,
                device: _key?.lastUsedDescription,
                lastUsedAt: _key?.lastUsedAt,
                onOpen: () {
                  final project = _project;
                  if (project != null) widget.onFinished(project);
                },
                onCancel: widget.onCancel,
              ),
            },
          ),
        ),
      ],
    );
  }
}

/// The left half: breadcrumb, video link, stepper, and whatever the step puts
/// under them. Every measurement in here is §2's, taken from the frame.
class _LeftPanel extends StatelessWidget {
  const _LeftPanel({required this.step, required this.child});

  final int step;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 80, right: 41),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Row(
            children: [
              Text(
                'Onboarding › New Project',
                style: T.supporting.copyWith(color: T.text3),
              ),
              const Spacer(),
              // Right-aligned, ending at x=742 — 662 into a panel that starts
              // at x=80.
              // The frame's "Watch this installation video": there is no
              // video, and the steps on this page are the install. What a
              // developer does not see here is the tester's side.
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () => Guide.leaveComment.show(context),
                  child: Text(
                    'How testers leave a comment',
                    style: T.supporting.copyWith(
                      color: T.text2,
                      decoration: TextDecoration.underline,
                      decorationColor: T.text2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Stepper at y=262 in the frame: 40 top, the breadcrumb's own 18,
          // then this.
          const SizedBox(height: 204),
          Stepper3(step: step),
          const SizedBox(height: 48),
          Expanded(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}

/// §2's horizontal stepper: three 40×24 pills with a striped connector.
///
/// The connector is six 2px bars with a 3px gap rather than a rule, which is
/// what the frame draws — and it carries state, so the line behind a finished
/// step is green before the pill after it turns blue.
class Stepper3 extends StatelessWidget {
  const Stepper3({super.key, required this.step});

  /// Zero-based index of the step in progress.
  final int step;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) _Connector(done: step > i - 1, active: step == i - 1),
            _Pill(index: i, step: step),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.index, required this.step});

  final int index;
  final int step;

  @override
  Widget build(BuildContext context) {
    final complete = step > index;
    final active = step == index;
    return Container(
      width: 40,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: complete ? T.green : (active ? T.accent : T.surface3),
        borderRadius: BorderRadius.circular(T.rPill),
      ),
      child: complete
          ? const Icon(Icons.check, size: 14, color: T.text1)
          : Text(
              '0${index + 1}',
              style: T.supporting.copyWith(
                color: active ? T.text1 : T.text3,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.done, required this.active});

  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colour = done ? T.green : (active ? T.accent : T.text3);
    return SizedBox(
      width: 28,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 6; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Container(width: 2, height: 10, color: colour),
          ],
        ],
      ),
    );
  }
}

/// Step 01 — name the project. Creating it is what mints the key.
class _StepName extends StatelessWidget {
  const _StepName({
    required this.controller,
    required this.busy,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Enter project name', style: T.heading),
        const SizedBox(height: 14),
        Text(
          'This can be changed later in project settings',
          style: T.supporting.copyWith(color: T.text3),
        ),
        const SizedBox(height: 13),
        SizedBox(
          width: 295,
          child: GField(
            controller: controller,
            hint: 'e.g. My App',
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 295,
          child: GButton(
            label: 'Continue',
            busy: busy,
            // Disabled until the field has something in it, then `--accent`.
            onPressed: controller.text.trim().isEmpty || busy ? null : onSubmit,
          ),
        ),
        // A dimmed button with no reason given stalled the first real walk
        // (27 Sep): the hint read as a name already filled in.
        if (controller.text.trim().isEmpty && !busy) ...[
          const SizedBox(height: 8),
          Text(
            'Type a name to continue.',
            style: T.supporting.copyWith(color: T.text3),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 295,
            child: Text(error!, style: T.supporting.copyWith(color: T.red)),
          ),
        ],
      ],
    );
  }
}

/// Step 02 — install the package. §9's first correction lives here: the frame
/// says `codestage_requester`, which is another company's package.
class _StepInstall extends StatelessWidget {
  const _StepInstall({required this.onDone});

  final VoidCallback onDone;

  /// The package page. It is a 404 until the SDK is published, which is
  /// honest: the button says where the package will live, and the copy above
  /// it is what actually installs it today from a path dependency.
  static final Uri _pubDev = Uri.parse('https://pub.dev/packages/guidester');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Install SDK', style: T.heading),
        const Text('in your Flutter app', style: T.heading),
        const SizedBox(height: 12),
        Text(
          "It won't work without installing the SDK",
          style: T.supporting.copyWith(color: T.text3),
        ),
        const SizedBox(height: 30),
        const CodeBlock(
          width: 343,
          height: 47,
          prefix: r'$',
          code: 'flutter pub add guidester',
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            GButtonOutlined(
              label: 'Open pub.dev',
              onPressed: () => unawaited(
                launchUrl(_pubDev, mode: LaunchMode.externalApplication),
              ),
            ),
            const SizedBox(width: 8),
            GButton(label: 'Yes, I have installed', onPressed: onDone),
          ],
        ),
      ],
    );
  }
}

/// Step 03 — the three lines of wiring, and then the live check.
class _StepWire extends StatelessWidget {
  const _StepWire({
    required this.endpoint,
    required this.apiKey,
    required this.connected,
    required this.device,
    required this.lastUsedAt,
    required this.onOpen,
    required this.onCancel,
  });

  final String endpoint;
  final String apiKey;
  final bool connected;
  final String? device;
  final DateTime? lastUsedAt;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  /// §9's second correction. The frame subclasses `CdsService`, which belongs
  /// to codestage.ro; this is the real API, with this project's own key
  /// already filled in.
  ///
  /// The key and, since D71, the endpoint: the package ships no backend URL,
  /// so `init` does not compile without one. The enabled flag stays gone (the
  /// key is the kill switch). The observer stays out: `MaterialApp.router`
  /// has no `navigatorObservers`, so the line would break every go_router
  /// app, and the SDK's console diagnostic names it for the apps that need
  /// it.
  String get _snippet => installSnippet(apiKey: apiKey, endpoint: endpoint);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add Guidester to your app', style: T.heading),
        const SizedBox(height: 10),
        Text(
          'Paste this into main.dart',
          style: T.supporting.copyWith(color: T.text3),
        ),
        const SizedBox(height: 12),
        // Ten lines of mono 13, one pixel tighter than the frame's 18. Everything
        // below it — the divider at y=455, the check, the two buttons at
        // y=583 — has to still fit above 752, so this step's rhythm is
        // tighter than step 01's.
        // Wider than the frame's 368: the real snippet carries the endpoint,
        // which the frame's placeholder did not, and the panel has the room.
        CodeBlock(width: 600, code: _snippet, copyable: true, lineHeight: 17),
        const SizedBox(height: 14),
        Container(width: 368, height: 1, color: T.line),
        const SizedBox(height: 14),
        ConnectionCheck(
          connected: connected,
          device: device,
          lastUsedAt: lastUsedAt,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(
              width: 178,
              child: GButtonOutlined(
                // Not "Finish later": finishing implies the project is
                // incomplete without this step, and it is not. The key exists,
                // the project exists, and a developer who leaves here has lost
                // nothing but the confirmation.
                label: 'Do this later',
                onPressed: onCancel,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 178,
              child: GButton(
                label: 'Open project',
                // Disabled until something has actually reported. The whole
                // reason this screen exists is that a developer cannot tell
                // "installed" from "installed and working", so finishing
                // before the SDK has spoken would restore the guess.
                onPressed: connected ? onOpen : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// §9's behavioural correction: `Do you see the comment bubble? Yes / No`
/// becomes a fact the backend already knows.
class ConnectionCheck extends StatelessWidget {
  const ConnectionCheck({
    super.key,
    required this.connected,
    this.device,
    this.lastUsedAt,
  });

  final bool connected;
  final String? device;
  final DateTime? lastUsedAt;

  @override
  Widget build(BuildContext context) {
    final detail = [
      ?device,
      if (lastUsedAt != null) _ago(lastUsedAt!),
    ].join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            connected
                ? const Icon(Icons.check_circle, size: 18, color: T.green)
                : const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(T.text3),
                    ),
                  ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                connected
                    ? (detail.isEmpty ? 'Connected' : 'Connected — $detail')
                    : 'Waiting for your first launch…',
                style: T.heading.copyWith(color: connected ? T.text1 : T.text2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 368,
          child: Text(
            connected
                ? 'The SDK reached this project. Anything a tester sends will '
                      'land on the board.'
                // Says the two things a developer would otherwise have to ask —
                // what to do, and whether they have to do anything else — and
                // deliberately promises no timeframe. A first debug build on a
                // cold machine can take minutes, and a line reading "in a few
                // seconds" would be wrong exactly when it is being read.
                : 'Launch your app in a debug build. This updates on its own.',
            style: T.supporting.copyWith(color: T.text3),
          ),
        ),
      ],
    );
  }

  /// Seconds up to a minute, then minutes, then a clock time. The frame says
  /// "2 seconds ago", and at minute one of an install that precision is the
  /// difference between "it worked" and "that was some earlier run".
  static String _ago(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inSeconds < 60) return '${delta.inSeconds} seconds ago';
    if (delta.inMinutes < 60) return '${delta.inMinutes} minutes ago';
    String two(int n) => n.toString().padLeft(2, '0');
    return 'at ${two(at.hour)}:${two(at.minute)}';
  }
}

/// A `--surface-1` block of mono 13 with an optional `$` prefix, per §2.
class CodeBlock extends StatefulWidget {
  const CodeBlock({
    super.key,
    required this.code,
    this.width,
    this.height,
    this.prefix,
    this.copyable = false,
    this.lineHeight,
    this.copyText,
  });

  final String code;
  final double? width;
  final double? height;
  final String? prefix;
  final bool copyable;

  /// What Copy puts on the clipboard, when it is not [code] itself: Settings
  /// shows a masked key and copies the real one.
  final String? copyText;

  /// Absolute line height in logical pixels, as §2 gives it. Null leaves the
  /// token's own.
  final double? lineHeight;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: T.surface1,
        borderRadius: BorderRadius.circular(T.rControl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.prefix != null) ...[
            Text(widget.prefix!, style: T.code.copyWith(color: T.text3)),
            const SizedBox(width: 8),
          ],
          Expanded(
            // Code does not wrap. A snippet reflowed at 368px stops being
            // something anyone can read as code — and the line that would
            // wrap first is the one carrying the key. It scrolls sideways,
            // and the Copy button is the path that does not involve reading
            // it at all.
            //
            // The scrollbar stays visible: without it, a key running past the
            // edge read as a broken box on the first real walk (27 Sep), not
            // as something that scrolls.
            child: RawScrollbar(
              controller: _scroll,
              thumbVisibility: true,
              thumbColor: T.text3,
              thickness: 4,
              radius: const Radius.circular(2),
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 10),
                child: SelectableText(
                  widget.code,
                  style: T.code.copyWith(
                    color: T.text1,
                    height: widget.lineHeight == null
                        ? 1.38
                        : widget.lineHeight! / T.code.fontSize!,
                  ),
                ),
              ),
            ),
          ),
          if (widget.copyable)
            GestureDetector(
              onTap: () async {
                await Clipboard.setData(
                  ClipboardData(text: widget.copyText ?? widget.code),
                );
                if (mounted) setState(() => _copied = true);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  _copied ? 'Copied' : 'Copy',
                  style: T.supporting.copyWith(color: T.accentText),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The two changes that install the SDK, for one project's key and this
/// deployment's endpoint. Onboarding and Settings show the same text.
String installSnippet({required String apiKey, required String endpoint}) =>
    'Guidester.init(\n'
    "  apiKey: '$apiKey',\n"
    "  endpoint: '$endpoint',\n"
    ');\n'
    '\n'
    'MaterialApp(\n'
    '  builder: (context, child) => GuidesterOverlay(child: child!),\n'
    ');';
