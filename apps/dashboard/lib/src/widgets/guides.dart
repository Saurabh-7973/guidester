import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Short, true how-tos opened from the learn card and onboarding. The frames
/// drew these as video links; there are no videos, so each is a few steps.
enum Guide {
  leaveComment('How to leave a comment', [
    'Open the test build. A round comment button sits on the screen; drag it '
        'out of the way if it covers something.',
    'Tap it, then tap the spot you mean. A pin marks it and the screen is '
        'captured.',
    'Write what went wrong, pick Blocked, Annoying or Cosmetic, and Send. The '
        'first time, it asks for your name.',
    'It lands here with the screenshot, the screen name, the device and the '
        'build.',
  ]),
  inviteTesters('How to invite testers', [
    'Build a test version with your key and endpoint: flutter build apk '
        '--dart-define=GUIDESTER_KEY=<key> '
        '--dart-define=GUIDESTER_ENDPOINT=<endpoint>',
    'Send that build the way you already do: Play internal or closed testing, '
        'Firebase App Distribution, or the APK itself.',
    'Testers need no account and nothing to install besides your app. Their '
        'comments arrive on this board.',
    'Leave the key out of your production build and the overlay is not there '
        'at all.',
  ]),

  nameScreens('How to name screens', [
    'Named routes (MaterialApp(routes: ...)): add '
        'navigatorObservers: [Guidester.observer] to your MaterialApp.',
    'go_router or MaterialApp.router: nothing to add. The Router names the '
        'screen.',
    'A screen with no route of its own, such as a tab or a sheet: wrap it in '
        "GuidesterScreen(name: 'CHECKOUT', child: ...) or call "
        "Guidester.setScreen('CHECKOUT').",
    'Check before testers do: every pin prints '
        '"[guidester] screen: NAME (layer n)" to the debug console.',
  ]);

  const Guide(this.title, this.steps);

  final String title;
  final List<String> steps;

  Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _GuideSheet(guide: this),
  );
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet({required this.guide});

  final Guide guide;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const ValueKey('guide-sheet'),
      backgroundColor: T.surface1,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(guide.title, style: T.heading)),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 18, color: T.text3),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < guide.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${i + 1}',
                          style: T.supporting.copyWith(color: T.accentText),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          guide.steps[i],
                          style: T.supporting.copyWith(color: T.text2),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
