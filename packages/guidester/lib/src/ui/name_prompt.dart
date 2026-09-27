import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Asked once per device, before the first send.
///
/// Carries the consent line: testers must be told a screenshot and their
/// device details leave the device.
class GuidesterNamePrompt extends StatefulWidget {
  const GuidesterNamePrompt({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<GuidesterNamePrompt> createState() => _GuidesterNamePromptState();
}

class _GuidesterNamePromptState extends State<GuidesterNamePrompt> {
  final TextEditingController _controller = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final valid = _controller.text.trim().isNotEmpty;
      if (valid != _valid) setState(() => _valid = valid);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Enter your name before sending feedback',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // §7: "Your name", not "Name (For your team)" — it goes to the
          // developer, not a team.
          const Text(
            'Your name',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          const Text(
            '(so the developer knows who reported what)',
            style: TextStyle(fontSize: 12, color: GT.text3),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) widget.onSubmit(v.trim());
            },
          ),
          const SizedBox(height: 12),
          // §7.1 consent gate. Always visible, not a link, not collapsed, and
          // nothing leaves the device before Continue.
          const Text(
            'Your feedback is sent with a screenshot of this screen and your '
            'device details.',
            style: TextStyle(fontSize: 12, color: GT.text3),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              button: true,
              enabled: _valid,
              label: 'Continue',
              child: FilledButton(
                onPressed: _valid
                    ? () => widget.onSubmit(_controller.text.trim())
                    : null,
                child: const Text('Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
