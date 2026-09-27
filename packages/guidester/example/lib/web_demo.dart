// The "Try it in your browser" page linked from pub.dev.
//
// Everything a visitor touches is the real package: the bubble, the pin, the
// composer, screen-name resolution, the screenshot and the tester-name prompt.
// Only the last step differs. Instead of posting to a Supabase project, the
// comment lands on the board next to the phone, so nothing a visitor types or
// captures leaves their browser and nobody's data is stored anywhere.
//
// Build:
//   flutter build web -t lib/web_demo.dart --base-href /guidester/
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:guidester/guidester.dart';
// ignore: implementation_imports
import 'package:guidester/src/api_client.dart' show ApiClient;
import 'package:http/http.dart' as http;

import 'main.dart' show ExampleApp;

@JS('window.open')
external void _openTab(String url, String target);

const _quickStart = 'https://pub.dev/packages/guidester#quick-start';
const _pubDev = 'https://pub.dev/packages/guidester';

void main() {
  // Any non-empty key and endpoint switch the SDK on. Neither is ever
  // contacted: the client below answers instead of the network.
  Guidester.init(apiKey: 'demo', endpoint: 'https://demo.invalid/ingest');
  runApp(const DemoPage());
}

/// One comment as the dashboard would show it.
class DemoComment {
  DemoComment(Map<String, dynamic> p)
    : body = '${p['body'] ?? ''}',
      screen = '${p['screen_name'] ?? 'UNKNOWN'}',
      impact = '${p['impact'] ?? 'annoying'}',
      tester = '${p['tester_name'] ?? 'Tester'}',
      device = '${p['device_model'] ?? 'this browser'}',
      os = '${p['os_version'] ?? ''}',
      tapX = (p['tap_x'] as num?)?.toDouble(),
      tapY = (p['tap_y'] as num?)?.toDouble(),
      errors = (p['errors'] as List?)?.length ?? 0,
      textScale = (p['context'] is Map)
          ? (p['context'] as Map)['text_scale']?.toString()
          : null,
      screenshot = p['screenshot_b64'] is String
          ? base64Decode(p['screenshot_b64'] as String)
          : null,
      at = DateTime.now();

  final String body, screen, impact, tester, device, os;
  final double? tapX, tapY;
  final int errors;
  final String? textScale;
  final Uint8List? screenshot;
  final DateTime at;
}

/// Stands in for the ingest function. Answers the launch ping, keeps every
/// comment in memory, and says "ok" the way the real function does.
class _BoardClient extends http.BaseClient {
  final ValueNotifier<List<DemoComment>> comments = ValueNotifier(const []);
  final ValueNotifier<bool> connected = ValueNotifier(false);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final raw = await request.finalize().bytesToString();
    final p = jsonDecode(raw) as Map<String, dynamic>;
    var answer = '{"ok":true}';
    if (p['ping'] == true) {
      connected.value = true;
      answer = '{"ok":true,"ping":true,"retests":[]}';
    } else if (p['verdict'] == null) {
      // A short wait, so "Sending" is visible the way it is on a real network.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      comments.value = [DemoComment(p), ...comments.value];
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(answer)),
      200,
      request: request,
    );
  }
}

const _bg = Color(0xFF0B0B0B);
const _panel = Color(0xFF161616);
const _line = Color(0xFF2A2A2A);
const _text2 = Color(0xFFB4B4B4);
const _text3 = Color(0xFF8B8B8B);
const _accent = Color(0xFF2F59ED);
const _amber = Color(0xFFF5A524);
const _phone = Size(360, 700);

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _client = _BoardClient();
  late final ApiClient _api = ApiClient(client: _client);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Try Guidester',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorSchemeSeed: _accent,
        useMaterial3: true,
      ),
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 980;
            // On a phone the frame has to fit the page: 16 px gutters and the
            // frame's own 20 px, never wider than the desktop size.
            final w = (c.maxWidth - 32 - 20).clamp(280.0, _phone.width);
            final size = wide
                ? _phone
                : Size(w, w * _phone.height / _phone.width);
            final phone = _PhoneFrame(
              size: size,
              child: ExampleApp(
                client: _api,
                frameSize: size,
                title: 'Try Guidester',
              ),
            );
            final board = _Board(client: _client);
            final content = wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      phone,
                      const SizedBox(width: 40),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _Intro(),
                            const SizedBox(height: 28),
                            board,
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Intro(),
                      const SizedBox(height: 24),
                      Center(child: phone),
                      const SizedBox(height: 32),
                      board,
                    ],
                  );
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 48 : 16,
                vertical: wide ? 24 : 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: content,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    const step = TextStyle(color: _text2, fontSize: 15, height: 1.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Try Guidester',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Text(
          'You are the tester. The phone runs the real package; the board is '
          'what your team would see.',
          style: TextStyle(color: _text2, fontSize: 16),
        ),
        SizedBox(height: 16),
        Text('1.  Tap the blue bubble in the phone.', style: step),
        Text(
          '2.  Tap anything that looks wrong. A pin drops there.',
          style: step,
        ),
        Text('3.  Type what is wrong and press Send.', style: step),
        Text(
          '4.  Watch it land on the board, with the screenshot and the '
          'screen it was on.',
          style: step,
        ),
        SizedBox(height: 8),
        Text(
          'Nothing leaves your browser. In your own app, comments go to your '
          'own Supabase project.',
          style: TextStyle(color: _text3, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () => _openTab(_quickStart, '_blank'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Set it up for your app  →'),
            ),
            OutlinedButton(
              onPressed: () => _openTab(_pubDev, '_blank'),
              child: const Text('pub.dev'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.size, required this.child});
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width + 20,
      height: size.height + 20,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: _line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: SizedBox.fromSize(size: size, child: child),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.client});
  final _BoardClient client;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Your dashboard',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: client.connected,
                builder: (_, on, _) => Row(
                  children: [
                    Icon(
                      on ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 16,
                      color: on ? const Color(0xFF22C55E) : _text3,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      on
                          ? 'Connected: the app reported in'
                          : 'Waiting for the app',
                      style: const TextStyle(color: _text2, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ValueListenableBuilder<List<DemoComment>>(
            valueListenable: client.comments,
            builder: (_, list, _) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        'No comments yet. Send one from the phone.',
                        style: TextStyle(color: _text3),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < list.length; i++)
                        _CommentCard(comment: list[i], expanded: i == 0),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment, required this.expanded});
  final DemoComment comment;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final meta = [
      c.impact.toUpperCase(),
      c.tester,
      c.device,
      // On the web the OS field is the browser's whole user-agent string,
      // which says nothing a reader wants. A phone sends "Android 15".
      if (c.os.isNotEmpty && c.os.length <= 30) c.os,
      if (c.textScale != null && c.textScale != '1.0')
        'text scale ${c.textScale}',
      if (c.errors > 0) '${c.errors} error${c.errors == 1 ? '' : 's'} attached',
    ].join('  •  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: expanded ? const Color(0xFF1F1F1F) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expanded && c.screenshot != null) ...[
            _Shot(comment: c),
            const SizedBox(width: 20),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    c.screen,
                    style: const TextStyle(
                      color: _amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(c.body, style: const TextStyle(fontSize: 17)),
                const SizedBox(height: 8),
                Text(meta, style: const TextStyle(color: _text3, fontSize: 12)),
                if (expanded) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'On your real board you would now mark it In progress or '
                    'Fixed. Marking it fixed asks this tester to check it on '
                    'their next launch.',
                    style: TextStyle(color: _text2, fontSize: 13, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The screenshot with the tester's pin drawn where they tapped.
class _Shot extends StatelessWidget {
  const _Shot({required this.comment});
  final DemoComment comment;

  @override
  Widget build(BuildContext context) {
    const w = 180.0;
    const h = w * 2;
    return SizedBox(
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.memory(comment.screenshot!, fit: BoxFit.cover),
            ),
            if (comment.tapX != null && comment.tapY != null)
              Positioned(
                left: comment.tapX! * w - 9,
                top: comment.tapY! * h - 9,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
