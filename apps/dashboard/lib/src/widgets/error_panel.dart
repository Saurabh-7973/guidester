import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/captured_error.dart';
import '../theme/tokens.dart';

/// What the app threw, under the comment that describes what it looked like.
///
/// A tester writes "the screen went white". This is the other half of that
/// sentence, and the reason it is worth a panel of its own rather than a line
/// in the device context: everything else on this screen describes the report,
/// and this describes the bug.
///
/// Rendered only when a comment carries errors, which most do not.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.errors});

  final List<CapturedError> errors;

  @override
  Widget build(BuildContext context) {
    if (errors.isEmpty) return const SizedBox.shrink();

    // Newest first. The tester wrote the comment after the last thing broke,
    // so the last thing to break is the one they are describing — but the
    // earlier ones stay, because the first error in a cascade is usually the
    // cause of the rest.
    final ordered = errors.reversed.toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: T.surface1,
        borderRadius: BorderRadius.circular(T.rPanel),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            errors.length == 1
                ? 'The app threw this'
                : 'The app threw these, newest first',
            style: T.ui.copyWith(color: T.text2),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < ordered.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: T.line),
              const SizedBox(height: 12),
            ],
            _Error(error: ordered[i]),
          ],
        ],
      ),
    );
  }
}

class _Error extends StatefulWidget {
  const _Error({required this.error});

  final CapturedError error;

  @override
  State<_Error> createState() => _ErrorState();
}

class _ErrorState extends State<_Error> {
  /// The stack is collapsed. The headline and the host frame answer the
  /// question most of the time, and twenty-four frames of framework under
  /// every error would bury the comment this panel sits below.
  bool _open = false;
  bool _copied = false;

  Future<void> _copy() async {
    final e = widget.error;
    await Clipboard.setData(ClipboardData(text: '${e.exception}\n${e.stack}'));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.error;
    final culprit = e.culprit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e.headline, style: T.code.copyWith(color: T.red, height: 1.5)),
        if (culprit != null) ...[
          const SizedBox(height: 8),
          // The frame that names somebody's own file. This is the line a
          // developer opens, so it is the one thing here that is not
          // collapsed behind a disclosure.
          SelectableText(culprit, style: T.code.copyWith(color: T.text1)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (e.at != null) _Meta(_time(e.at!)),
            if (e.screen != null) _Meta(e.screen!),
            if (e.library != null) _Meta(e.library!),
            if (culprit == null && e.stack.isNotEmpty)
              // Saying so is better than leaving a developer to wonder why the
              // file line is missing: a layout assertion thrown inside
              // RenderFlex genuinely has no host frame.
              const _Meta('framework frames only'),
            if (e.stack.isEmpty) const _Meta('no stack'),
          ],
        ),
        if (e.stack.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _LinkButton(
                label: _open ? 'Hide stack' : 'Show stack',
                onPressed: () => setState(() => _open = !_open),
              ),
              const SizedBox(width: 16),
              _LinkButton(label: _copied ? 'Copied' : 'Copy', onPressed: _copy),
            ],
          ),
        ],
        if (_open) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: T.page,
              borderRadius: BorderRadius.circular(T.rControl),
            ),
            padding: const EdgeInsets.all(12),
            // A stack line is long and must not wrap into porridge, so it
            // scrolls sideways inside its own box rather than reflowing.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                e.stack,
                style: T.code.copyWith(color: T.text2, height: 1.6),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Wall-clock, because the only comparison that matters is against the
  /// comment's own timestamp sitting a few lines above it.
  static String _time(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: T.meta.copyWith(color: T.text3));
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Text(label, style: T.supporting.copyWith(color: T.accentText)),
      ),
    );
  }
}
