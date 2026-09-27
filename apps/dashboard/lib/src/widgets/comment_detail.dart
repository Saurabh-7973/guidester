import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/comment.dart';
import '../models/issue_export.dart';
import '../theme/tokens.dart';
import 'context_panel.dart';
import 'error_panel.dart';
import 'guides.dart';
import 'screenshot_view.dart';

/// The right pane of §6: the comment, centred, over its screenshot.
///
/// The frame puts a light photographic backdrop behind the screenshot. That is
/// a second theme to maintain, and the screenshot reads better lit against
/// dark, so this uses `--surface-1` instead.
class CommentDetail extends StatefulWidget {
  const CommentDetail({
    super.key,
    required this.comment,
    required this.signedUrl,
    this.screenshotExpired = false,
    this.onScreenshotFailed,
    this.link,
    this.onPrev,
    this.onNext,
    this.onBack,
    this.onDelete,
    this.onDeleteTester,
    this.workflow,
  });

  final Comment comment;
  final String? signedUrl;
  final bool screenshotExpired;
  final VoidCallback? onScreenshotFailed;

  /// This comment's shareable URL. Null hides Copy link.
  final String? link;

  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// Shown under 720, where the rail is gone and this is the whole screen.
  final VoidCallback? onBack;

  /// G4. Irreversible, and takes the screenshot with it.
  final VoidCallback? onDelete;

  /// "Remove everything of mine" — what a request under the DPDP Act actually
  /// looks like. Null when the comment carries no tester id.
  final VoidCallback? onDeleteTester;

  /// The verdicts, blocker, assignee and history. Null in contexts that only
  /// read — a golden, or a preview.
  final Widget? workflow;

  @override
  State<CommentDetail> createState() => _CommentDetailState();
}

class _CommentDetailState extends State<CommentDetail> {
  /// §6: collapsed by default. It appears in no frame, and it is the field
  /// that answers "which device were you on?" — the thing the fourteen-day
  /// test actually measures.
  bool _contextOpen = false;

  final _scroll = ScrollController();

  @override
  void didUpdateWidget(CommentDetail old) {
    super.didUpdateWidget(old);
    // Field test: Next kept the previous scroll offset, so the new comment
    // opened with its own title scrolled away.
    if (old.comment.id != widget.comment.id) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openLightbox() {
    if (widget.comment.screenshotPath == null || widget.signedUrl == null) {
      return;
    }
    showDialog<void>(
      context: context,
      barrierColor: T.page.withValues(alpha: 0.9),
      builder: (context) => Dialog(
        key: const ValueKey('lightbox'),
        backgroundColor: T.page,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            maxScale: 4,
            child: ScreenshotView(
              comment: widget.comment,
              signedUrl: widget.signedUrl,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface1,
        borderRadius: BorderRadius.circular(T.rPanel),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onBack != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                child: InkWell(
                  onTap: widget.onBack,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back, size: 16, color: T.text3),
                      const SizedBox(width: 6),
                      Text(
                        'All comments',
                        style: T.supporting.copyWith(color: T.text3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Home (8): side by side where the pane is wide, so the
                // screenshot is sized to the height there is and the triage
                // controls sit beside it instead of under it. Stacked (and
                // scrolling) only when the pane is too narrow for both.
                if (constraints.maxWidth >= _sideBySide) {
                  return Column(
                    children: [
                      ..._head(),
                      const SizedBox(height: 20),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LayoutBuilder(
                              builder: (context, box) => SizedBox(
                                // A phone screenshot is about 0.46 as wide as
                                // tall; the height decides, within limits.
                                width: (box.maxHeight * 0.5).clamp(220, 420),
                                height: box.maxHeight,
                                child: _shot(),
                              ),
                            ),
                            const SizedBox(width: 28),
                            Expanded(
                              child: SingleChildScrollView(
                                key: const ValueKey('detail-scroll'),
                                controller: _scroll,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _extras(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return SingleChildScrollView(
                  key: const ValueKey('detail-scroll'),
                  controller: _scroll,
                  child: Column(
                    children: [
                      ..._head(),
                      const SizedBox(height: 28),
                      Center(child: SizedBox(width: 400, child: _shot())),
                      ..._extras(),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Prev, Delete and Next share one row: a row of its own for Delete
          // was the difference between fitting a laptop screen and scrolling.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.onPrev != null)
                _NavLink(label: '« Prev comment', onTap: widget.onPrev!),
              Expanded(
                child: widget.onDelete == null
                    ? const SizedBox.shrink()
                    : Center(
                        child: _DeleteControls(
                          // One confirmation per comment. Without the key the
                          // open state outlived a delete and offered the next
                          // tester's "delete everything, no undo" (27 Sep).
                          key: ValueKey(widget.comment.id),
                          onDelete: widget.onDelete!,
                          onDeleteTester: widget.onDeleteTester,
                          testerName: widget.comment.testerName,
                        ),
                      ),
              ),
              if (widget.onNext != null)
                _NavLink(label: 'Next comment »', onTap: widget.onNext!),
            ],
          ),
        ],
      ),
    );
  }

  /// Wider than this, the screenshot and the triage controls sit side by
  /// side and nothing scrolls but the controls, if they must.
  static const double _sideBySide = 680;

  List<Widget> _head() => [
    // 20/600, centred, at most 68 characters per line. The
    // measure is what keeps a long comment readable centred;
    // without it, centred text at this width is a wall.
    ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _measure),
      child: Text(
        widget.comment.body,
        textAlign: TextAlign.center,
        style: T.heading,
      ),
    ),
    const SizedBox(height: 12),
    _CentredMeta(comment: widget.comment),
    // §5.6 row 17: UNKNOWN is an install problem with a fix, not a name.
    if (widget.comment.screenName == 'UNKNOWN') ...[
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          const Icon(Icons.help_outline, size: 14, color: T.amber),
          Text(
            'Screen not detected',
            style: T.supporting.copyWith(color: T.amber),
          ),
          InkWell(
            onTap: () => Guide.nameScreens.show(context),
            child: Text(
              'How to name screens',
              style: T.supporting.copyWith(
                color: T.accentText,
                decoration: TextDecoration.underline,
                decorationColor: T.accentText,
              ),
            ),
          ),
        ],
      ),
    ],
    const SizedBox(height: 8),
    Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: [
        if (widget.link != null)
          _CopyAction(
            key: ValueKey('copy-link-${widget.comment.id}'),
            label: 'Copy link',
            done: 'Link copied',
            icon: Icons.link,
            text: () => widget.link!,
          ),
        // For the tracker the team already lives in: the facts a developer
        // asks the tester for, as Markdown GitHub, Jira and Linear all read.
        _CopyAction(
          key: ValueKey('copy-issue-${widget.comment.id}'),
          label: 'Copy as issue',
          done: 'Issue copied',
          icon: Icons.bug_report_outlined,
          text: () => issueMarkdown(widget.comment, link: widget.link),
        ),
      ],
    ),
  ];

  Widget _shot() => MouseRegion(
    cursor: SystemMouseCursors.zoomIn,
    child: GestureDetector(
      onTap: _openLightbox,
      child: ScreenshotView(
        comment: widget.comment,
        signedUrl: widget.signedUrl,
        expired: widget.screenshotExpired,
        onFailed: widget.onScreenshotFailed,
      ),
    ),
  );

  List<Widget> _extras() => [
    if (widget.comment.errors.isNotEmpty) ...[
      const SizedBox(height: 24),
      // Above the device context, not inside it. What broke
      // outranks what the screen brightness was.
      ErrorPanel(errors: widget.comment.errors),
    ],
    const SizedBox(height: 12),
    _ContextDisclosure(
      open: _contextOpen,
      onToggle: () => setState(() => _contextOpen = !_contextOpen),
    ),
    if (_contextOpen) ...[
      const SizedBox(height: 12),
      ContextPanel(comment: widget.comment),
    ],
    if (widget.workflow != null) ...[
      const SizedBox(height: 16),
      Container(height: 1, color: T.line),
      const SizedBox(height: 16),
      widget.workflow!,
    ],
  ];

  /// 68 characters at the heading size. Measured once rather than guessed at:
  /// `20 * 0.5` is the usual average advance for Inter's lowercase.
  static const double _measure = 68 * 20 * 0.5;
}

/// The meta row again, centred and uppercase, under the comment.
class _CentredMeta extends StatelessWidget {
  const _CentredMeta({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          comment.impact.label,
          style: T.meta.copyWith(color: comment.impact.color),
        ),
        const Text(' • ', style: T.meta),
        Text((comment.testerName ?? 'Unknown').toUpperCase(), style: T.meta),
        const Text(' • ', style: T.meta),
        Text(comment.screenName, style: T.meta),
      ],
    );
  }
}

class _ContextDisclosure extends StatelessWidget {
  const _ContextDisclosure({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onToggle,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: T.text3,
            ),
            const SizedBox(width: 6),
            Text(
              open ? 'Hide device context' : 'Show device context',
              style: T.supporting.copyWith(color: T.text3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Text(label, style: T.supporting.copyWith(color: T.text3)),
      ),
    );
  }
}

/// Deletion, behind a confirmation.
///
/// Irreversible and it takes the screenshot with it, so it does not sit one
/// stray click from Resolve. The second control is the one a request under the
/// Act actually looks like: not "remove comment 4" but "remove everything of
/// mine".
class _DeleteControls extends StatefulWidget {
  const _DeleteControls({
    super.key,
    required this.onDelete,
    required this.onDeleteTester,
    required this.testerName,
  });

  final VoidCallback onDelete;
  final VoidCallback? onDeleteTester;
  final String? testerName;

  @override
  State<_DeleteControls> createState() => _DeleteControlsState();
}

class _DeleteControlsState extends State<_DeleteControls> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    if (!_confirming) {
      return Align(
        alignment: Alignment.center,
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: () => setState(() => _confirming = true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.delete_outline, size: 16, color: T.text3),
                const SizedBox(width: 6),
                Text('Delete', style: T.supporting.copyWith(color: T.text3)),
              ],
            ),
          ),
        ),
      );
    }

    final who = widget.testerName ?? 'this tester';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delete this comment and its screenshot? You can undo for 5 seconds.',
          style: T.supporting.copyWith(color: T.text2),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _DangerButton(
              label: 'Delete comment',
              onTap: () {
                setState(() => _confirming = false);
                widget.onDelete();
              },
            ),
            if (widget.onDeleteTester != null)
              _DangerButton(
                // Not deferred: many rows at once, and it is a data-erasure request.
                label: 'Delete everything from $who, no undo',
                onTap: () {
                  setState(() => _confirming = false);
                  widget.onDeleteTester!();
                },
              ),
            Semantics(
              button: true,
              child: InkWell(
                onTap: () => setState(() => _confirming = false),
                child: Text(
                  'Cancel',
                  style: T.supporting.copyWith(color: T.text3),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rControl),
        child: Container(
          height: T.controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(T.rControl),
            border: Border.all(color: T.red),
          ),
          child: Text(label, style: T.supporting.copyWith(color: T.red)),
        ),
      ),
    );
  }
}

/// Copies text and says so in place, until the comment changes (the key
/// carries the comment id).
class _CopyAction extends StatefulWidget {
  const _CopyAction({
    super.key,
    required this.label,
    required this.done,
    required this.icon,
    required this.text,
  });

  final String label;
  final String done;
  final IconData icon;
  final String Function() text;

  @override
  State<_CopyAction> createState() => _CopyActionState();
}

class _CopyActionState extends State<_CopyAction> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text()));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: _copied ? widget.done : widget.label,
    excludeSemantics: true,
    onTap: _copy,
    child: InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(T.rControl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_copied ? Icons.check : widget.icon, size: 14, color: T.text3),
            const SizedBox(width: 6),
            Text(
              _copied ? widget.done : widget.label,
              style: T.supporting.copyWith(color: T.text3),
            ),
          ],
        ),
      ),
    ),
  );
}
