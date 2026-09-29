import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../impact.dart';
import '../theme/tokens.dart';
import 'impact_chips.dart';

/// The comment sheet, shown once a pin is placed.
///
/// Deliberately a plain [TextField]: `feedback`'s custom text handling is the
/// source of their Samsung backspace bug (#281).
class GuidesterComposer extends StatefulWidget {
  const GuidesterComposer({
    super.key,
    required this.screenName,
    required this.onSend,
    required this.onCancel,
    required this.sending,
    this.error,
    this.initialText = '',
    this.initialImpact = Impact.fallback,
    this.blankWarning,
    this.onChanged,
    this.restoredFrom,
    this.onMarkup,
    this.marks = 0,
    this.screenshot,
    this.onPreview,
    this.screenshotNote,
  });

  final String screenName;

  /// Impact is never null: the row defaults to [Impact.fallback] and cannot
  /// be emptied, so there is no unset state to carry.
  final void Function(String text, Impact impact) onSend;
  final VoidCallback onCancel;
  final bool sending;
  final String? error;
  final String initialText;
  final Impact initialImpact;

  /// Shown when part of the screen cannot be captured. Not an error — the
  /// report is still worth sending; the tester just needs to know the picture
  /// will not show what they are pointing at.
  final String? blankWarning;

  /// Every edit to the text or the impact, so the overlay can keep the draft
  /// somewhere that outlives the process.
  final void Function(String text, Impact impact)? onChanged;

  /// The screen an unsent comment brought back from an earlier launch was
  /// written on, or null when this comment is new.
  final String? restoredFrom;

  /// Opens the screenshot to draw on. Null hides the button: no screenshot
  /// was captured, so there is nothing to mark.
  final VoidCallback? onMarkup;

  /// Strokes already drawn, for the button's label.
  final int marks;

  /// The screenshot that will be sent — redacted, and with any mark-up burned
  /// in — shown as a thumbnail so every tester sees it, not only those who
  /// open the markup view. Null hides the thumbnail.
  final Uint8List? screenshot;

  /// Opens [screenshot] full screen.
  final VoidCallback? onPreview;

  /// Why no screenshot is attached, when one was withheld. Never says what was
  /// hidden.
  final String? screenshotNote;

  @override
  State<GuidesterComposer> createState() => _GuidesterComposerState();
}

class _GuidesterComposerState extends State<GuidesterComposer> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  bool _hasText = false;
  late Impact _impact = widget.initialImpact;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.trim().isNotEmpty;
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      widget.onChanged?.call(_controller.text, _impact);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Text is never cleared on failure — the tester keeps what they wrote.
  String get currentText => _controller.text;

  @override
  Widget build(BuildContext context) {
    final canSend = _hasText && !widget.sending;
    return Semantics(
      container: true,
      label: 'Write a comment about ${widget.screenName}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // §6: the resolved screen name, muted, above the field. It is a
              // live test of the resolver — a wrong tag or UNKNOWN is seen on
              // day two by a tester, not on day fourteen in the dashboard.
              // §4: on failure the error takes this row; the typed text stays.
              Expanded(
                child: widget.error != null
                    ? Semantics(
                        liveRegion: true,
                        child: Text(
                          widget.error!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: GT.red,
                          ),
                        ),
                      )
                    : Text(
                        widget.screenName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: GT.text3,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              Semantics(
                button: true,
                label: 'Discard this comment',
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.sending ? null : widget.onCancel,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          GuidesterImpactChips(
            selected: _impact,
            enabled: !widget.sending,
            onChanged: (impact) {
              setState(() => _impact = impact);
              widget.onChanged?.call(_controller.text, impact);
            },
          ),
          if (widget.restoredFrom != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.history, size: 14, color: GT.text3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Unsent comment from ${widget.restoredFrom}, kept from '
                    'last time.',
                    style: const TextStyle(fontSize: 12, color: GT.text3),
                  ),
                ),
              ],
            ),
          ],
          if (widget.blankWarning != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: GT.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.blankWarning!,
                      style: const TextStyle(fontSize: 12, color: GT.amber),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (widget.screenshotNote != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Row(
                key: const ValueKey('guidester-screenshot-note'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.image_not_supported_outlined,
                    size: 14,
                    color: GT.amber,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.screenshotNote!,
                      style: const TextStyle(fontSize: 12, color: GT.amber),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            maxLength: 2000,
            enabled: !widget.sending,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What went wrong?',
              border: OutlineInputBorder(),
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.screenshot != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Semantics(
                    button: true,
                    label: 'View the screenshot that will be sent',
                    child: GestureDetector(
                      key: const ValueKey('guidester-thumbnail'),
                      onTap: widget.sending ? null : widget.onPreview,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 36,
                          height: 48,
                          color: GT.surface2,
                          child: Image.memory(
                            widget.screenshot!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.onMarkup != null)
                TextButton.icon(
                  key: const ValueKey('guidester-markup'),
                  onPressed: widget.sending ? null : widget.onMarkup,
                  icon: Icon(
                    widget.marks == 0 ? Icons.draw_outlined : Icons.check,
                    size: 16,
                  ),
                  label: Text(
                    widget.marks == 0 ? 'Mark up screenshot' : 'Marked up',
                  ),
                ),
              const Spacer(),
              Semantics(
                button: true,
                enabled: canSend,
                label: 'Send comment',
                child: FilledButton.icon(
                  // Guarded by `sending`: their #345 has shipped duplicate
                  // reports on double-tap since Jan 2025.
                  onPressed: canSend
                      ? () => widget.onSend(_controller.text.trim(), _impact)
                      : null,
                  icon: widget.sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                  label: Text(widget.sending ? 'Sending' : 'Send'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
