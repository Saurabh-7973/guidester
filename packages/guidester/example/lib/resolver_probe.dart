// A release-mode probe for layer 4, and the only honest way to answer two
// questions that a widget test cannot.
//
// 1. Does the D66 rule hold in AOT? The host shape it was written for —
//    Snapdrop's `HomeScreen` rendering a `DropDownView` inline — is rebuilt
//    here class for class.
// 2. Does `flutter build --obfuscate` mangle layer 4? Layer 4 reads
//    `runtimeType.toString()`, and nothing in a debug build or a widget test
//    can tell you what that returns once the snapshot is obfuscated.
//
// Build and read the answer off logcat:
//   flutter build apk --release -t lib/resolver_probe.dart
//   flutter build apk --release --obfuscate --split-debug-info=build/sym \
//     -t lib/resolver_probe.dart
//
// It prints one line per case, prefixed `[probe]`, and nothing else.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
// The resolver is not part of the public API and should not be: hosts wrap a
// screen, they do not ask what one is called. This probe is a diagnostic that
// ships inside the package's own example, and it needs the answer layer 4
// gives rather than the one a route name would.
// ignore: implementation_imports
import 'package:guidester/src/screen_resolver.dart';

void main() => runApp(const ProbeApp());

/// The component Snapdrop's main screen renders inside itself. The name is
/// copied deliberately: this is the class that used to win.
class DropDownView extends StatelessWidget {
  const DropDownView({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Snapdrop's main screen, in the only shape that matters here: it renders the
/// component inline, as its body, rather than pushing it as a route.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(children: [Expanded(child: DropDownView())]);
}

class ProbeApp extends StatefulWidget {
  const ProbeApp({super.key});

  @override
  State<ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<ProbeApp> {
  final GlobalKey _boundaryKey = GlobalKey();
  String _line = 'resolving…';

  @override
  void initState() {
    super.initState();
    // After the first frame, so the tree is mounted — the failure mode that
    // made the widget-test walk report the right answer for the wrong reason.
    SchedulerBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  void _resolve() {
    final root = _boundaryKey.currentContext as Element?;
    if (root == null) return;
    // The overlay resolves from its own RepaintBoundary, never from the tap.
    final r = ScreenResolver.resolveDetailed(root, searchRoot: root);
    final line =
        '[probe] resolved=${r.name} layer=${r.layer} '
        'runtimeType=${const HomeScreen().runtimeType} '
        'nested=${const DropDownView().runtimeType}';
    debugPrint(line);
    setState(() => _line = line);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const HomeScreen(),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_line, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
